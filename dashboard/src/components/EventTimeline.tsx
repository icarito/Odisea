import React from 'react';
import { AlertCircle, Skull, LogIn, MapPin, Pause, Play, RotateCcw } from 'lucide-react';
import type { TelemetryEvent } from '../types';

interface EventTimelineProps {
  events: TelemetryEvent[];
}

// El timestamp de los eventos puede llegar en ms (contrato v2) o en segundos
// (filas historicas del central). Normalizar a ms para formatear.
const eventTimeMs = (value: unknown): number => {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return 0;
  return n < 1e12 ? n * 1000 : n;
};

interface EventDisplay {
  icon: React.ComponentType<{ size?: number }>;
  colorClass: string;
  message: string;
}

// `scene_enter` es el nombre que usa el central; en el dashboard el evento ya
// existia como `scene_change`, asi que se unifican.
const KINDS: Record<string, EventDisplay> = {
  death: { icon: Skull, colorClass: 'text-danger', message: 'Muerte' },
  scene_change: { icon: MapPin, colorClass: 'text-accent', message: 'Cambio de escena' },
  session_start: { icon: LogIn, colorClass: 'text-success', message: 'Inicio de sesión' },
  respawn: { icon: RotateCcw, colorClass: 'text-success', message: 'Respawn' },
  pause: { icon: Pause, colorClass: 'text-warning', message: 'Pausa' },
  resume: { icon: Play, colorClass: 'text-success', message: 'Reanudado' },
};

const describeEvent = (event: TelemetryEvent): EventDisplay => {
  const type = event.type === 'scene_enter' ? 'scene_change' : event.type;
  const base = KINDS[type] || {
    icon: AlertCircle,
    colorClass: 'text-text-muted',
    message: type,
  };
  const data = event.data || {};
  const scene = String(data.to || event.scene || '');
  switch (type) {
    case 'death': {
      const cause = data.cause ? ` (${data.cause})` : '';
      return { ...base, message: scene ? `Muerte en ${scene}${cause}` : `Muerte${cause}` };
    }
    case 'scene_change': {
      const from = data.from ? `${data.from} → ` : '';
      const load = Number(data.load_ms);
      const loadText = Number.isFinite(load) && load > 0 ? ` · ${Math.round(load)} ms` : '';
      return { ...base, message: `${from}${scene || '?'}${loadText}` };
    }
    default:
      return base;
  }
};

export const EventTimeline: React.FC<EventTimelineProps> = ({ events }) => {
  return (
    <div className="flex flex-col gap-2">
      {events.map((event, idx) => {
        const key = `${event.session_id || ''}-${event.seq ?? idx}`;
        // session_start no es un evento mas: marca el arranque de una sesion
        // nueva, se ve como separador en vez de item de la lista.
        if (event.type === 'session_start') {
          return (
            <div key={key} className="flex items-center gap-2 py-1">
              <span className="h-px flex-1 bg-black/10" />
              <span className="text-[0.5rem] font-black uppercase tracking-widest text-success">nueva sesión</span>
              <span className="h-px flex-1 bg-black/10" />
            </div>
          );
        }
        const { icon: Icon, colorClass, message } = describeEvent(event);
        const label = event.player_id || 'jugador';
        return (
          <div key={key} className="flex items-start gap-2 border-l-2 border-black/10 pl-3 py-1 ml-2">
            <div className={`mt-0.5 ${colorClass}`}>
              <Icon size={12} />
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex justify-between items-baseline gap-2">
                <span className="text-[0.625rem] font-black uppercase truncate">{label}</span>
                <span className="text-[0.5rem] font-bold text-text-muted whitespace-nowrap">
                  {new Date(eventTimeMs(event.timestamp)).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                </span>
              </div>
              <p className="text-[0.5625rem] text-text-muted leading-tight truncate">{message}</p>
            </div>
          </div>
        );
      })}
      {events.length === 0 && (
        <div className="py-4 text-center text-[0.5rem] italic text-text-muted uppercase tracking-widest">
          Sin actividad reciente
        </div>
      )}
    </div>
  );
};
