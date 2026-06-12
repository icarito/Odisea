// Hotzone upload worker
self.onmessage = async function(e) {
  var {url, token, blob, b64, id, headers} = e.data;
  try {
    if (!blob && b64) {
      var bin = atob(b64);
      var bytes = new Uint8Array(bin.length);
      for (var i = 0; i < bin.length; i++) {
        bytes[i] = bin.charCodeAt(i);
      }
      blob = bytes;
    }
    var fetchHeaders = {
      'Authorization': 'Bearer ' + token,
      'Content-Type': 'application/octet-stream'
    };
    if (headers) {
      Object.assign(fetchHeaders, headers);
    }
    var resp = await fetch(url, {
      method: 'POST',
      headers: fetchHeaders,
      body: blob
    });
    self.postMessage({id: id, ok: resp.ok, status: resp.status});
  } catch (err) {
    self.postMessage({id: id, ok: false, error: err.message});
  }
};
