import React from 'react';
import { UserPlus, UserMinus, Flame, AlertTriangle } from 'lucide-react';

interface TimelineEvent {
  id: string;
  type: 'connect' | 'disconnect' | 'hotzone' | 'alert';
  playerId: string;
  playerName: string;
  timestamp: number;
  message: string;
  scene?: string;
}

interface EventTimelineProps {
  events: TimelineEvent[];
}

export const EventTimeline: React.FC<EventTimelineProps> = ({ events }) => {
  if (events.length === 0) {
    return (
      <div className="flex items-center justify-center py-8 text-xs italic text-text-muted">
        No hay eventos recientes
      </div>
    );
  }

  return (
    <div className="flex flex-col">
      {events.map((event, i) => (
        <div 
          key={event.id} 
          className={`flex gap-3 px-3 py-2 border-l-2 transition-colors hover:bg-bg-primary/50 ${
            i !== events.length - 1 ? 'border-b border-black/5' : ''
          } ${
            event.type === 'hotzone' ? 'border-l-warning' :
            event.type === 'alert' ? 'border-l-danger' :
            'border-l-accent'
          }`}
        >
          <div className="shrink-0 mt-0.5">
            {event.type === 'connect' && <UserPlus size={14} className="text-success" />}
            {event.type === 'disconnect' && <UserMinus size={14} className="text-danger" />}
            {event.type === 'hotzone' && <Flame size={14} className="text-warning" />}
            {event.type === 'alert' && <AlertTriangle size={14} className="text-danger" />}
          </div>
          
          <div className="min-w-0 flex-1">
            <div className="flex items-center justify-between gap-2">
              <span className="truncate text-[0.625rem] font-black uppercase text-text-primary">
                {event.playerName || event.playerId.slice(0, 8)}
              </span>
              <span className="shrink-0 text-[0.5rem] font-mono text-text-muted">
                {new Date(event.timestamp * 1000).toLocaleTimeString('es', { 
                  hour: '2-digit', 
                  minute: '2-digit',
                  second: '2-digit'
                })}
              </span>
            </div>
            <div className="truncate text-[0.625rem] text-text-muted mt-0.5">
              {event.message}
              {event.scene && <span className="text-accent ml-1">· {event.scene}</span>}
            </div>
          </div>
        </div>
      ))}
    </div>
  );
};
