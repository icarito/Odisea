import { useState, useEffect } from 'react';
import { getWebTelemetry } from '../api';

interface WebTelemetryRecord {
  event: 'loader_start' | 'engine_start' | 'player_released';
  ts?: number;
  session_id: string;
  received_at: string;
  ua?: string;
  load_ms?: number;
  total_ms?: number;
}

interface WebLoad {
  sessionId: string;
  startTs: number;
  ua?: string;
  engineMs?: number;
  playerMs?: number;
}

function groupBySession(records: WebTelemetryRecord[]): WebLoad[] {
  const loads: Record<string, WebLoad> = {};
  for (const rec of records) {
    if (!rec.session_id) continue;
    const load = loads[rec.session_id] ||= {
      sessionId: rec.session_id,
      startTs: 0,
    };
    if (rec.event === 'loader_start') {
      load.startTs = rec.ts || Date.parse(rec.received_at) || 0;
      load.ua = rec.ua;
    } else if (rec.event === 'engine_start') {
      load.engineMs = rec.load_ms;
      if (!load.startTs && rec.ts && rec.load_ms) load.startTs = rec.ts - rec.load_ms;
    } else if (rec.event === 'player_released') {
      load.playerMs = rec.total_ms;
      if (!load.startTs && rec.ts && rec.total_ms) load.startTs = rec.ts - rec.total_ms;
    }
  }
  return Object.values(loads).sort((a, b) => b.startTs - a.startTs);
}

const fmtSecs = (ms?: number) =>
  typeof ms === 'number' && isFinite(ms) ? `${(ms / 1000).toFixed(1)}s` : '…';

const browserOf = (ua?: string) => {
  if (!ua) return '';
  if (ua.includes('Firefox/')) return 'Firefox';
  if (ua.includes('Edg/')) return 'Edge';
  if (ua.includes('Chrome/')) return 'Chrome';
  if (ua.includes('Safari/')) return 'Safari';
  return 'Otro';
};

export function WebLoads() {
  const [loads, setLoads] = useState<WebLoad[]>([]);
  const [error, setError] = useState(false);

  useEffect(() => {
    let alive = true;
    const poll = async () => {
      try {
        const records = await getWebTelemetry();
        if (alive) {
          setLoads(groupBySession(records));
          setError(false);
        }
      } catch {
        if (alive) setError(true);
      }
    };
    poll();
    const timer = setInterval(poll, 15000);
    return () => { alive = false; clearInterval(timer); };
  }, []);

  if (error) return <div className="text-center text-text-muted py-4 text-xs">Sin datos de cargas</div>;
  if (loads.length === 0) return <div className="text-center text-text-muted py-4 text-xs">Sin cargas web</div>;

  return (
    <div className="flex flex-col gap-1">
      <div className="flex text-[9px] uppercase text-text-muted font-bold px-2">
        <span className="flex-1">Inicio</span>
        <span className="w-14 text-right" title="loader_start → engine_start">Engine</span>
        <span className="w-14 text-right" title="loader_start → player con control en la primera escena">Player</span>
      </div>
      {loads.slice(0, 20).map(load => (
        <div
          key={load.sessionId}
          className="flex items-center px-2 py-1 border border-border-custom bg-bg-card rounded text-[11px]"
          title={`${load.sessionId}\n${load.ua || ''}`}
        >
          <span className="flex-1 text-text-muted truncate">
            {load.startTs ? new Date(load.startTs).toLocaleTimeString() : '—'}
            {load.ua ? ` · ${browserOf(load.ua)}` : ''}
          </span>
          <span className="w-14 text-right">{fmtSecs(load.engineMs)}</span>
          <span className="w-14 text-right text-accent font-bold">{fmtSecs(load.playerMs)}</span>
        </div>
      ))}
    </div>
  );
}
