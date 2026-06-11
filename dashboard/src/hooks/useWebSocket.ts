import { useState, useEffect, useCallback, useRef } from 'react';

const WS_URL = `${window.location.protocol === 'https:' ? 'wss:' : 'ws:'}//${window.location.host}/events`;

export function useWebSocket() {
  const [lastMessage, setLastMessage] = useState<any>(null);
  const [status, setStatus] = useState<'connecting' | 'open' | 'closed'>('connecting');
  const ws = useRef<WebSocket | null>(null);
  const reconnectTimeout = useRef<number | null>(null);

  const connect = useCallback(() => {
    const token = sessionStorage.getItem("odisea_token");
    if (!token) return;

    if (ws.current) ws.current.close();

    // In dev, we might need to point to a specific host
    const url = import.meta.env.DEV ? `ws://localhost:5003/events` : WS_URL;

    // Unfortunately we can't send headers in browser WebSocket API.
    // Usually tokens are passed via subprotocols or query params.
    // For this bridge, let's assume we might need a query param if auth is enforced on /events.
    // However, the current odisea_central.py _auth_guard expects Bearer header.
    // Standard browser WebSockets don't support headers.
    // FIX: The server should probably allow token in query param for /events or handle it after connection.

    ws.current = new WebSocket(`${url}?token=${token}`);

    ws.current.onopen = () => {
      setStatus('open');
      console.log("WebSocket Connected");
    };

    ws.current.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        setLastMessage(data);
      } catch (e) {
        console.error("Failed to parse WS message", e);
      }
    };

    ws.current.onclose = () => {
      setStatus('closed');
      console.log("WebSocket Closed, reconnecting...");
      reconnectTimeout.current = window.setTimeout(connect, 3000);
    };

    ws.current.onerror = (err) => {
      console.error("WebSocket Error", err);
      ws.current?.close();
    };
  }, []);

  useEffect(() => {
    connect();
    return () => {
      if (reconnectTimeout.current) clearTimeout(reconnectTimeout.current);
      if (ws.current) ws.current.close();
    };
  }, [connect]);

  return { lastMessage, status };
}
