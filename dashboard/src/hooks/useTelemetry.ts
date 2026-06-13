import { useState, useEffect, useRef } from 'react';
import { getStatus, getHealth } from '../api';
import type { HeartbeatMap, Alert } from '../types';
import { saveSnapshot, getSnapshot } from '../lib/pushStorage';

export const useTelemetry = () => {
  const [heartbeats, setHeartbeats] = useState<HeartbeatMap>({});
  const [peersConnected, setPeersConnected] = useState<number | string>('?');
  const [heartbeatRate, setHeartbeatRate] = useState<number | string>('?');
  const [isConnected, setIsConnected] = useState(true);
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [health, setHealth] = useState<any>({});
  const disconnectedPids = useRef<Set<string>>(new Set());
  const playerLabels = useRef<Record<string, string>>({});
  const pollCount = useRef(0);
  const GHOST_STORE_INTERVAL = 10; // Only write to history every N polls
  const historyRef = useRef<Record<string, {
    fps: number[],
    memory: number[],
    trail: [number, number, number][],
    lastPos: [number, number, number] | null,
    lastTick: number,
    lastMoveTime: number,
    lastScene: string,
    events: { scene: string, zone: string, mode: string, timestamp: number }[]
  }>>({});

  useEffect(() => {
    const poll = async () => {
      try {
        let data: HeartbeatMap;
        try {
          data = await getStatus();
          await saveSnapshot('status', data);
          setIsConnected(true);
        } catch (e) {
          data = await getSnapshot('status') || {};
          setIsConnected(false);
        }
        setHeartbeats(data);

        const now = Date.now();
        const newAlerts: Alert[] = [];
        pollCount.current++;
        const shouldWriteGhost = pollCount.current % GHOST_STORE_INTERVAL === 0;

        Object.entries(data).forEach(([pid, hb]) => {
          playerLabels.current[pid] = hb.display_name || pid;
          if (!historyRef.current[pid]) {
            historyRef.current[pid] = {
                fps: [],
                memory: [],
                trail: [],
                lastPos: null,
                lastTick: 0,
                lastMoveTime: now,
                lastScene: '',
                events: []
            };
          }
          const hist = historyRef.current[pid];

          // FPS & Memory History (handle incomplete heartbeats) — throttle to ghost store interval
          if (shouldWriteGhost) {
            hist.fps = [...hist.fps, hb.player?.fps ?? 0].slice(-300);
            hist.memory = [...hist.memory, hb.player?.memory_mb ?? 0].slice(-300);
          }

          // Events (Scene/Zone/Mode change)
          const lastEvent = hist.events[hist.events.length - 1];
          const scene = hb.player?.scene ?? '';
          const zone = hb.player?.zone ?? '';
          const mode = hb.player?.mode ?? '';
          
          if (!lastEvent ||
              lastEvent.scene !== scene ||
              lastEvent.zone !== zone ||
              lastEvent.mode !== mode) {
            hist.events = [...hist.events, {
                scene: scene,
                zone: zone,
                mode: mode,
                timestamp: now / 1000
            }];
          }

          // Trail — every heartbeat, no throttle, no distance threshold.
          // Clear trail when scene changes (new session / teleport) to avoid
          // a long line crossing the entire level geometry.
          const currentScene = hb.player?.scene ?? '';
          if (currentScene !== hist.lastScene) {
            hist.trail = [];
            hist.lastScene = currentScene;
          }

          const rawPos = hb.player?.position;
          if (Array.isArray(rawPos) && rawPos.length >= 3) {
            const pos: [number, number, number] = [Number(rawPos[0]), Number(rawPos[1]), Number(rawPos[2])];
            hist.trail = [...hist.trail, pos].slice(-600);
            hist.lastPos = pos;
            hist.lastMoveTime = now;
          }

          // Alerts: solo desconexiones y errores del backend.
          // Alertas de low FPS, memory spike y softlock eliminadas para reducir ruido.
        });

        // Disconnect check (evitar bucle infinito marcando los ya procesados)
        Object.keys(historyRef.current).forEach(pid => {
          if (!data[pid] && !disconnectedPids.current.has(pid)) {
            disconnectedPids.current.add(pid);
            const label = playerLabels.current[pid] || pid;
            newAlerts.push({
              id: `${pid}-disconnect-${now}`,
              type: 'disconnect',
              message: `${label} disconnected`,
              timestamp: now,
              playerId: pid
            });
            // No borramos de historyRef para mantener los gráficos congelados
          }
        });

        if (newAlerts.length > 0) {
           setAlerts(prev => [...newAlerts, ...prev].slice(0, 50));
        }

        try {
          const health = await getHealth();
          setHealth(health);
          setPeersConnected(health.peers_connected ?? '?');
          setHeartbeatRate(health.heartbeats_rate ?? '?');
          await saveSnapshot('health', health);
        } catch (e) {
          const health = await getSnapshot('health') || {};
          setHealth(health);
          setPeersConnected(health.peers_connected ?? '?');
          setHeartbeatRate(health.heartbeats_rate ?? '?');
        }
      } catch (e) {
        console.error("Telemetry poll failed", e);
      }
    };

    poll();
    const interval = setInterval(poll, 1000);
    return () => clearInterval(interval);
  }, []);

  return { heartbeats, peersConnected, heartbeatRate, isConnected, alerts, history: historyRef.current, health };
};
