// ANNAV2 WebSocket Worker
// Runs WebSocket connection entirely off the main thread (browser Web Worker).
// Communicates with the HTML shell (which exposes window.ANNAV2_WS_Bridge) via postMessage.
// Godot calls window.ANNAV2_WS_Bridge methods via JavaScript.eval().

var ws = null;
var pendingIncoming = []; // messages from server → Godot

self.onmessage = function(e) {
	var msg = e.data;
	switch (msg.cmd) {
		case "connect":
			if (ws && (ws.readyState === WebSocket.CONNECTING || ws.readyState === WebSocket.OPEN)) {
				self.postMessage({ cmd: "log", text: "[ANNAV2-Worker] Already connected/connecting, closing old socket first" });
				ws.close();
			}
			pendingIncoming.length = 0;
			var url = msg.url;
			try {
				ws = new WebSocket(url);
				ws.binaryType = "arraybuffer";
			} catch (err) {
				self.postMessage({ cmd: "error", text: "[ANNAV2-Worker] WebSocket constructor failed: " + err.message });
				self.postMessage({ cmd: "state", state: 3 }); // closed
				return;
			}
			self.postMessage({ cmd: "log", text: "[ANNAV2-Worker] Connecting to " + url });

			ws.onopen = function() {
				self.postMessage({ cmd: "log", text: "[ANNAV2-Worker] Connected" });
				self.postMessage({ cmd: "state", state: 1 }); // open
			};

			ws.onclose = function(event) {
				self.postMessage({ cmd: "log", text: "[ANNAV2-Worker] Disconnected (code=" + event.code + ")" });
				self.postMessage({ cmd: "state", state: 3 }); // closed
				ws = null;
			};

			ws.onerror = function(event) {
				self.postMessage({ cmd: "log", text: "[ANNAV2-Worker] Error on socket" });
				self.postMessage({ cmd: "state", state: 3 }); // closed
			};

			ws.onmessage = function(event) {
				var text;
				if (typeof event.data === "string") {
					text = event.data;
				} else if (event.data instanceof ArrayBuffer) {
					var decoder = new TextDecoder("utf-8");
					text = decoder.decode(new Uint8Array(event.data));
				} else {
					self.postMessage({ cmd: "log", text: "[ANNAV2-Worker] Unknown message type" });
					return;
				}
				pendingIncoming.push(text);
			};
			break;

		case "disconnect":
			if (ws) {
				ws.close();
				ws = null;
			}
			pendingIncoming.length = 0;
			self.postMessage({ cmd: "state", state: 3 });
			break;

		case "send":
			if (ws && ws.readyState === WebSocket.OPEN) {
				ws.send(msg.text);
			} else {
				self.postMessage({ cmd: "log", text: "[ANNAV2-Worker] send ignored: socket not open" });
			}
			break;

		case "poll":
			var take = msg.max || 16;
			var out = pendingIncoming.splice(0, take);
			self.postMessage({ cmd: "pollResult", messages: out });
			break;

		case "getState":
			var state = ws ? ws.readyState : 3;
			self.postMessage({ cmd: "state", state: state });
			break;

		default:
			self.postMessage({ cmd: "log", text: "[ANNAV2-Worker] Unknown command: " + msg.cmd });
	}
};
