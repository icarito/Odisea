import React from 'react';
import { AlertCircle, Skull, LogIn, MapPin, Pause, Play, RotateCcw } from 'lucide-react';
import type { TelemetryEvent } from '../types';
import { formatSeconds } from '../lib/filters';

interface EventTimelineProps {
  events: TelemetryEvent[];
}

// El timestamp de los eventos puede llegar en ms (contrato v2) o en segundos
// (filas historicas del central). Normalizar a ms para formatear y ordenar.
export const eventTimeMs = (value: unknown): number => {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return 0;
  return n < 1e12 ? n * 1000 : n;
};

// El central emite `scene_enter`; en el dashboard el evento existia como
// `scene_change`. Unificar para iconos, color y agrupacion.
export const normalizeEventType = (type: string): string =>
  type === 'scene_enter' ? 'scene_change' : type;

// Paleta compartida con los marcadores de SessionPlayback y LiveCombinedChart.
export const EVENT_COLORS: Record<string, string> = {
  death: '#f85149',
  scene_change: '#7fd1ff',
  session_start: '#3fb950',
  respawn: '#3fb950',
  pause: '#d29922',
  resume: '#3fb950',
};

const EVENT_ICONS: Record<string, React.ComponentType<{ size?: number }>> = {
  death: Skull,
  scene_change: MapPin,
  session_start: LogIn,
  respawn: RotateCcw,
  pause: Pause,
  resume: Play,
};

export interface EventDisplay {
  icon: React.ComponentType<{ size?: number }>;
  color: string;
  message: string;
}

// Mensaje e icono/color de un evento. Reusado por la lista del playback.
export const describeTelemetryEvent = (event: TelemetryEvent): EventDisplay => {
  const type = normalizeEventType(String(event.type || ''));
  const data = (event.data || {}) as Record<string, any>;
  const scene = String(data.to || event.scene || '');
  const icon = EVENT_ICONS[type] || AlertCircle;
  const color = EVENT_COLORS[type] || '#8b949e';
  switch (type) {
    case 'death': {
      const cause = data.cause ? ` (${data.cause})` : '';
      return { icon, color, message: scene ? `Muerte en ${scene}${cause}` : `Muerte${cause}` };
    }
    case 'scene_change': {
      const from = data.from ? `${data.from} → ` : '';
      const load = Number(data.load_ms);
      const loadText = Number.isFinite(load) && load > 0 ? ` · ${formatSeconds(load)}` : '';
      return { icon, color, message: `${from}${scene || '?'}${loadText}` };
    }
    default:
      return { icon, color, message: type };
  }
};

const formatRelative = (ms: number, now: number): string => {
  if (!ms) return '';
  const secs = Math.max(0, Math.round((now - ms) / 1000));
  if (secs < 5) return 'ahora';
  if (secs < 60) return `hace ${secs}s`;
  if (secs < 3600) return `hace ${Math.round(secs / 60)}m`;
  if (secs < 86400) return `hace ${Math.round(secs / 3600)}h`;
  return `hace ${Math.round(secs / 86400)}d`;
};

interface EventGroup {
  key: string;
  sessionId: string;
  playerId: string;
  events: TelemetryEvent[];
}

const groupBySession = (events: TelemetryEvent[]): EventGroup[] => {
  const groups = new Map<string, EventGroup>();
  for (const ev of events) {
    const sessionId = String(ev.session_id || '');
    const playerId = String(ev.player_id || '');
    const key = sessionId || playerId || 'sin-sesion';
    let group = groups.get(key);
    if (!group) {
      group = { key, sessionId, playerId, events: [] };
      groups.set(key, group);
    }
    group.events.push(ev);
  }
  // Dentro de cada sesion, cronologico. La sesion con actividad mas reciente,
  // primero.
  const list = [...groups.values()];
  list.forEach((g) => g.events.sort((a, b) => eventTimeMs(a.timestamp) - eventTimeMs(b.timestamp)));
  list.sort((a, b) => {
    const la = eventTimeMs(a.events[a.events.length - 1]?.timestamp);
    const lb = eventTimeMs(b.events[b.events.length - 1]?.timestamp);
    return lb - la;
  });
  return list;
};

const shortId = (id: string) => (id ? id.slice(0, 8) : '');

export const EventTimeline: React.FC<EventTimelineProps> = ({ events }) => {
  const now = Date.now();
  const groups = groupBySession(Array.isArray(events) ? events : []);

  return (
    <div className="flex flex-col gap-3">
      {groups.map((group) => {
        const latest = eventTimeMs(group.events[group.events.length - 1]?.timestamp);
        return (
          <div key={group.key} className="flex flex-col gap-1">
            <div className="flex items-center gap-2">
              <span className="h-px flex-1 bg-black/10" />
              <span className="whitespace-nowrap text-[0.5rem] font-black uppercase tracking-widest text-text-muted">
                {group.sessionId ? `sesión ${shortId(group.sessionId)}` : (group.playerId || 'sin sesión')}
              </span>
              <span className="whitespace-nowrap text-[0.5rem] font-bold text-text-muted/70">{formatRelative(latest, now)}</span>
              <span className="h-px flex-1 bg-black/10" />
            </div>
            {group.events.slice().reverse().map((event, idx) => {
              const { icon: Icon, color, message } = describeTelemetryEvent(event);
              const ms = eventTimeMs(event.timestamp);
              return (
                <div key={`${event.seq ?? idx}-${ms}`} className="ml-2 flex items-start gap-2 border-l-2 border-black/10 py-1 pl-3">
                  <div className="mt-0.5" style={{ color }}>
                    <Icon size={12} />
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-baseline justify-between gap-2">
                      <span className="min-w-0 truncate text-[0.625rem] font-black uppercase">{message}</span>
                      <span
                        className="whitespace-nowrap text-[0.5rem] font-bold text-text-muted"
                        title={ms ? new Date(ms).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : ''}
                      >
                        {formatRelative(ms, now)}
                      </span>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        );
      })}
      {groups.length === 0 && (
        <div className="py-4 text-center text-[0.5rem] italic uppercase tracking-widest text-text-muted">
          Sin actividad reciente
        </div>
      )}
    </div>
  );
};
