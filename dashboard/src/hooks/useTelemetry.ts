import { useState, useEffect, useRef } from 'react';
import { getStatus, getHealth } from '../api';
import type { HeartbeatMap, Alert } from '../types';

export const useTelemetry = () => {
  const [heartbeats, setHeartbeats] = useState<HeartbeatMap>({});
  const [peersConnected, setPeersConnected] = useState<number | string>('?');
  const [isConnected, setIsConnected] = useState(true);
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const historyRef = useRef<Record<string, {
    fps: number[],
    memory: number[],
    trail: [number, number, number][],
    lastPos: [number, number, number] | null,
    lastTick: number,
    lastMoveTime: number,
    lowFpsStartTime: number | null,
    initialMemory: number | null,
    events: { scene: string, zone: string, mode: string, timestamp: number }[]
  }>>({});

  useEffect(() => {
    const poll = async () => {
      try {
        const data: HeartbeatMap = await getStatus();
        setHeartbeats(data);
        setIsConnected(true);

        const now = Date.now();
        const newAlerts: Alert[] = [];

        Object.entries(data).forEach(([pid, hb]) => {
          if (!historyRef.current[pid]) {
            historyRef.current[pid] = {
                fps: [],
                memory: [],
                trail: [],
                lastPos: null,
                lastTick: 0,
                lastMoveTime: now,
                lowFpsStartTime: null,
                initialMemory: hb.player?.memory_mb ?? 0,
                events: []
            };
          }
          const hist = historyRef.current[pid];

          // FPS & Memory History (handle incomplete heartbeats)
          hist.fps = [...hist.fps, hb.player?.fps ?? 0].slice(-300);
          hist.memory = [...hist.memory, hb.player?.memory_mb ?? 0].slice(-300);

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

          // Trail (conversión estricta a números para evitar corrupción en Three.js)
          const rawPos = hb.player?.position;
          if (Array.isArray(rawPos) && rawPos.length >= 3) {
            const pos: [number, number, number] = [Number(rawPos[0]), Number(rawPos[1]), Number(rawPos[2])];
            
            if (!hist.lastPos ||
                Math.abs(pos[0] - hist.lastPos[0]) > 0.1 ||
                Math.abs(pos[1] - hist.lastPos[1]) > 0.1 ||
                Math.abs(pos[2] - hist.lastPos[2]) > 0.1) {
              hist.trail = [...hist.trail, pos].slice(-120);
              hist.lastPos = pos;
              hist.lastMoveTime = now;
            }
          }

          // Alerts
          // FPS Bajo: < 30 por > 5s
          const currentFps = hb.player?.fps ?? 60;
          if (currentFps < 30) {
            if (!hist.lowFpsStartTime) hist.lowFpsStartTime = now;
            if (now - hist.lowFpsStartTime > 5000) {
              newAlerts.push({
                id: `${pid}-lowfps-${now}`,
                type: 'low_fps',
                message: `FPS bajo detectado en ${pid.slice(0,8)} (< 30)`,
                timestamp: now,
                playerId: pid
              });
              hist.lowFpsStartTime = now; // Reset to avoid spamming every second
            }
          } else {
            hist.lowFpsStartTime = null;
          }

          // Memory Leak: > 20% spike (simplified check vs initial or sliding window)
          const currentMem = hb.player?.memory_mb ?? 0;
          if (hist.initialMemory && currentMem > hist.initialMemory * 1.2) {
            newAlerts.push({
                id: `${pid}-memleak-${now}`,
                type: 'memory_leak',
                message: `Posible memory leak en ${pid.slice(0,8)} (+20%)`,
                timestamp: now,
                playerId: pid
            });
            hist.initialMemory = currentMem; // Reset baseline
          }

          // Nota: Alertas de 'stale' y 'softlock' eliminadas para reducir ruido visual.
          // Solo se notifican desconexiones y problemas críticos de rendimiento.
        });

        // Disconnect check
        Object.keys(historyRef.current).forEach(pid => {
          if (!data[pid]) {
             newAlerts.push({
              id: `${pid}-disconnect-${now}`,
              type: 'disconnect',
              message: `Player ${pid.slice(0,8)} disconnected`,
              timestamp: now,
              playerId: pid
            });
            // We don't delete from historyRef to keep charts frozen
          }
        });

        if (newAlerts.length > 0) {
           setAlerts(prev => [...newAlerts, ...prev].slice(0, 50));
        }

        const health = await getHealth();
        setPeersConnected(health.peers_connected ?? '?');
      } catch (e) {
        setIsConnected(false);
        console.error("Telemetry poll failed", e);
      }
    };

    poll();
    const interval = setInterval(poll, 1000);
    return () => clearInterval(interval);
  }, []);

  return { heartbeats, peersConnected, isConnected, alerts, history: historyRef.current };
};
