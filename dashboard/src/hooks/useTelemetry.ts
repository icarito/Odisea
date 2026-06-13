import { useState, useEffect, useRef, useCallback } from 'react';
import { getStatus, getHealth } from '../api';
import type { Heartbeat, HeartbeatMap, Alert } from '../types';
import { saveSnapshot, getSnapshot } from '../lib/pushStorage';

// Live telemetry is delivered by the central over WebSocket (/events): it pushes
// each heartbeat as it arrives, so the dashboard no longer polls /status every
// second (which, over the ~0.5-1.5s round-trip to the server, made the UI lag).
// We seed the map once with a GET, then keep it live from the WS stream. /health
// is polled separately because it carries deploy/version metadata.

const HEALTH_POLL_MS = 5000;
// Drop a player from the live map this long after its last heartbeat. The WS
// stream only adds players, so staleness is detected by a periodic sweep.
const STALE_AFTER_MS = 12000;
const SWEEP_MS = 2000;
const SNAPSHOT_EVERY_MS = 5000;

const wsBaseFromApiTarget = () => {
  const apiTarget = import.meta.env.VITE_API_TARGET;
  if (apiTarget) return apiTarget.replace(/^http/, 'ws').replace(/\/$/, '');
  return `${window.location.protocol === 'https:' ? 'wss:' : 'ws:'}//${window.location.host}`;
};
const EVENTS_WS_URL = `${wsBaseFromApiTarget()}/events`;

interface PlayerHistory {
  fps: number[];
  memory: number[];
  trail: [number, number, number][];
  lastPos: [number, number, number] | null;
  lastTick: number;
  lastMoveTime: number;
  lastScene: string;
  events: { scene: string; zone: string; mode: string; timestamp: number }[];
}

type PlayerHistoryMap = Record<string, PlayerHistory>;

interface PublishedBuild {
  game_version?: string;
  git_commit?: string;
  build_id?: string;
  build_channel?: string;
  timestamp?: number;
}

interface HealthPayload {
  peers_connected?: number | string;
  heartbeats_rate?: number | string;
  dashboard_version?: string;
  dashboard_deployed_at?: number | null;
  latest_published?: PublishedBuild;
}

type HeartbeatMessage = Heartbeat & { type?: string };

const isHeartbeatMessage = (msg: unknown): msg is HeartbeatMessage => {
  if (!msg || typeof msg !== 'object') return false;
  const candidate = msg as Partial<HeartbeatMessage>;
  return candidate.type !== 'alert' && typeof candidate.player_id === 'string' && !!candidate.player;
};

export const useTelemetry = () => {
  const [heartbeats, setHeartbeats] = useState<HeartbeatMap>({});
  const [peersConnected, setPeersConnected] = useState<number | string>('?');
  const [heartbeatRate, setHeartbeatRate] = useState<number | string>('?');
  const [isConnected, setIsConnected] = useState(true);
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [health, setHealth] = useState<HealthPayload>({});
  const [history, setHistory] = useState<PlayerHistoryMap>({});
  const disconnectedPids = useRef<Set<string>>(new Set());
  const playerLabels = useRef<Record<string, string>>({});
  // Wall-clock ms of the last heartbeat seen per player, for the stale sweep.
  const lastSeenMs = useRef<Record<string, number>>({});
  const ghostTick = useRef<Record<string, number>>({});
  const lastSnapshotMs = useRef(0);
  const GHOST_STORE_EVERY = 10; // sample fps/mem into history every N heartbeats
  const historyRef = useRef<PlayerHistoryMap>({});

  // Fold a single heartbeat into the per-player history (fps/mem buffers, trail,
  // scene/zone/mode events). Shared by the WS path and the initial GET seed.
  const ingestHeartbeat = useCallback((pid: string, hb: Heartbeat) => {
    const now = Date.now();
    lastSeenMs.current[pid] = now;
    playerLabels.current[pid] = hb.display_name || pid;
    disconnectedPids.current.delete(pid);

    if (!historyRef.current[pid]) {
      historyRef.current[pid] = {
        fps: [], memory: [], trail: [], lastPos: null,
        lastTick: 0, lastMoveTime: now, lastScene: '', events: [],
      };
    }
    const hist = historyRef.current[pid];
    hist.lastTick = Number(hb.player?.tick ?? hist.lastTick ?? 0);

    ghostTick.current[pid] = (ghostTick.current[pid] || 0) + 1;
    if (ghostTick.current[pid] % GHOST_STORE_EVERY === 0) {
      hist.fps = [...hist.fps, hb.player?.fps ?? 0].slice(-300);
      hist.memory = [...hist.memory, hb.player?.memory_mb ?? 0].slice(-300);
    }

    const lastEvent = hist.events[hist.events.length - 1];
    const scene = hb.player?.scene ?? '';
    const zone = hb.player?.zone ?? '';
    const mode = hb.player?.mode ?? '';
    if (!lastEvent || lastEvent.scene !== scene || lastEvent.zone !== zone || lastEvent.mode !== mode) {
      hist.events = [...hist.events, { scene, zone, mode, timestamp: now / 1000 }];
    }

    // Clear the trail on scene change (new session / teleport).
    if (scene !== hist.lastScene) {
      hist.trail = [];
      hist.lastScene = scene;
    }

    const rawPos = hb.player?.position;
    if (Array.isArray(rawPos) && rawPos.length >= 3) {
      const pos: [number, number, number] = [Number(rawPos[0]), Number(rawPos[1]), Number(rawPos[2])];
      hist.trail = [...hist.trail, pos].slice(-600);
      hist.lastPos = pos;
      hist.lastMoveTime = now;
    }
    setHistory({ ...historyRef.current });
  }, []);

  const ingestHeartbeatMap = useCallback((data: HeartbeatMap) => {
    Object.entries(data).forEach(([pid, hb]) => ingestHeartbeat(pid, hb));
  }, [ingestHeartbeat]);

  const saveStatusSnapshotSoon = useCallback((data: HeartbeatMap) => {
    const now = Date.now();
    if (now - lastSnapshotMs.current < SNAPSHOT_EVERY_MS) return;
    lastSnapshotMs.current = now;
    saveSnapshot('status', data).catch(() => {});
  }, []);

  // --- Heartbeats over WebSocket (push) ---
  useEffect(() => {
    let disposed = false;
    let socket: WebSocket | null = null;
    let reconnectTimer: number | null = null;

    // Seed the map once so the view isn't empty until the first WS frame. Also
    // serves as the offline fallback (cached snapshot when the GET fails).
    (async () => {
      try {
        const data: HeartbeatMap = await getStatus();
        if (disposed) return;
        await saveSnapshot('status', data);
        ingestHeartbeatMap(data);
        setHeartbeats(data);
      } catch {
        const cached = (await getSnapshot('status')) || {};
        if (!disposed) {
          ingestHeartbeatMap(cached);
          setHeartbeats(cached);
        }
      }
    })();

    const connect = () => {
      if (disposed) return;
      const token = localStorage.getItem('odisea_token');
      if (!token) return;
      socket = new WebSocket(`${EVENTS_WS_URL}?token=${token}`);

      socket.onopen = () => { if (!disposed) setIsConnected(true); };

      socket.onmessage = (event) => {
        let msg: unknown;
        try { msg = JSON.parse(event.data) as unknown; } catch { return; }
        // Alerts are handled by useWebSocket; here we only fold in heartbeats.
        // A heartbeat carries a player_id and a nested player object.
        if (isHeartbeatMessage(msg)) {
          ingestHeartbeat(msg.player_id, msg);
          setHeartbeats((prev) => {
            const next = { ...prev, [msg.player_id]: msg };
            saveStatusSnapshotSoon(next);
            return next;
          });
        }
      };

      socket.onclose = () => {
        if (disposed) return;
        setIsConnected(false);
        reconnectTimer = window.setTimeout(connect, 3000);
      };
      socket.onerror = () => { socket?.close(); };
    };
    connect();

    return () => {
      disposed = true;
      if (reconnectTimer) clearTimeout(reconnectTimer);
      if (socket) { socket.onclose = null; socket.close(); }
    };
  }, [ingestHeartbeat, ingestHeartbeatMap, saveStatusSnapshotSoon]);

  // --- Stale sweep: prune players whose last heartbeat is too old, and raise a
  // single disconnect alert for each. Replaces the poll's map-diff logic. ---
  useEffect(() => {
    const sweep = () => {
      const now = Date.now();
      const stale: string[] = [];
      for (const pid of Object.keys(lastSeenMs.current)) {
        if (now - lastSeenMs.current[pid] > STALE_AFTER_MS) stale.push(pid);
      }
      if (stale.length === 0) return;

      const newAlerts: Alert[] = [];
      for (const pid of stale) {
        if (!disconnectedPids.current.has(pid)) {
          disconnectedPids.current.add(pid);
          newAlerts.push({
            id: `${pid}-disconnect-${now}`,
            type: 'disconnect',
            message: `${playerLabels.current[pid] || pid} disconnected`,
            timestamp: now,
            playerId: pid,
          });
        }
        delete lastSeenMs.current[pid];
      }
      if (newAlerts.length) setAlerts((prev) => [...newAlerts, ...prev].slice(0, 50));
      // Remove stale players from the live map (history is kept frozen).
      setHeartbeats((prev) => {
        const next = { ...prev };
        for (const pid of stale) delete next[pid];
        return next;
      });
    };
    const id = setInterval(sweep, SWEEP_MS);
    return () => clearInterval(id);
  }, []);

  // --- Health: slow poll (small aggregate, not per-frame). ---
  useEffect(() => {
    const loadHealth = async () => {
      try {
        const h = await getHealth() as HealthPayload;
        setHealth(h);
        setPeersConnected(h.peers_connected ?? '?');
        setHeartbeatRate(h.heartbeats_rate ?? '?');
        await saveSnapshot('health', h);
      } catch {
        const cached = ((await getSnapshot('health')) || {}) as HealthPayload;
        setHealth(cached);
        setPeersConnected(cached.peers_connected ?? '?');
        setHeartbeatRate(cached.heartbeats_rate ?? '?');
      }
    };
    loadHealth();
    const id = setInterval(loadHealth, HEALTH_POLL_MS);
    return () => clearInterval(id);
  }, []);

  return { heartbeats, peersConnected, heartbeatRate, isConnected, alerts, history, health };
};
