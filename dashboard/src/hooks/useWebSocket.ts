import { useState, useEffect, useRef } from 'react';

const wsBaseFromApiTarget = () => {
  const apiTarget = import.meta.env.VITE_API_TARGET;
  if (apiTarget) return apiTarget.replace(/^http/, 'ws').replace(/\/$/, '');
  return `${window.location.protocol === 'https:' ? 'wss:' : 'ws:'}//${window.location.host}`;
};

const WS_URL = `${wsBaseFromApiTarget()}/events`;

export function useWebSocket() {
  const [lastMessage, setLastMessage] = useState<any>(null);
  const [status, setStatus] = useState<'connecting' | 'open' | 'closed'>('connecting');
  const ws = useRef<WebSocket | null>(null);
  const reconnectTimeout = useRef<number | null>(null);

  useEffect(() => {
    // `disposed` guards against StrictMode's mount→unmount→mount in dev and
    // against the reconnect cascade: an intentional close must NOT schedule
    // a new connect.
    let disposed = false;

    const connect = () => {
      if (disposed) return;

      const token = sessionStorage.getItem("odisea_token");
      if (!token) return;

      // In central-dev mode, connect directly to the remote WSS endpoint instead
      // of tunneling through Vite's WS proxy, which is prone to EPIPE when the
      // upstream closes/reconnects. The token goes in the query param because
      // the browser WebSocket API can't send Authorization headers.
      const socket = new WebSocket(`${WS_URL}?token=${token}`);
      ws.current = socket;

      socket.onopen = () => {
        if (disposed) { socket.close(); return; }
        setStatus('open');
        console.log("WebSocket Connected");
      };

      socket.onmessage = (event) => {
        try {
          setLastMessage(JSON.parse(event.data));
        } catch (e) {
          console.error("Failed to parse WS message", e);
        }
      };

      socket.onclose = () => {
        setStatus('closed');
        // Only reconnect if this close wasn't us tearing down, and the socket
        // that closed is still the current one (ignore stale sockets).
        if (disposed || ws.current !== socket) return;
        console.log("WebSocket Closed, reconnecting...");
        reconnectTimeout.current = window.setTimeout(connect, 3000);
      };

      socket.onerror = () => {
        // Let onclose handle reconnection; closing here would double-fire.
        socket.close();
      };
    };

    connect();

    return () => {
      disposed = true;
      if (reconnectTimeout.current) clearTimeout(reconnectTimeout.current);
      const socket = ws.current;
      ws.current = null;
      if (socket) {
        socket.onclose = null; // prevent the teardown close from scheduling a reconnect
        socket.close();
      }
    };
  }, []);

  return { lastMessage, status };
}
