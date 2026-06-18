import React from 'react';
import { AlertCircle, LogOut, LogIn, MapPin } from 'lucide-react';

interface EventTimelineProps {
  events: any[];
}

export const EventTimeline: React.FC<EventTimelineProps> = ({ events }) => {
  return (
    <div className="flex flex-col gap-2">
      {events.map((event, idx) => {
        const Icon = event.type === 'disconnect' ? LogOut : 
                     event.type === 'low_fps' ? AlertCircle :
                     event.type === 'scene_change' ? MapPin : LogIn;
        
        const colorClass = event.type === 'disconnect' ? 'text-danger' :
                          event.type === 'low_fps' ? 'text-warning' :
                          event.type === 'scene_change' ? 'text-accent' : 'text-success';

        return (
          <div key={idx} className="flex items-start gap-2 border-l-2 border-black/10 pl-3 py-1 ml-2">
            <div className={`mt-0.5 ${colorClass}`}>
              <Icon size={12} />
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex justify-between items-baseline gap-2">
                <span className="text-[0.625rem] font-black uppercase truncate">{event.playerName || event.playerId}</span>
                <span className="text-[0.5rem] font-bold text-text-muted whitespace-nowrap">
                  {new Date(event.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                </span>
              </div>
              <p className="text-[0.5625rem] text-text-muted leading-tight truncate">{event.message}</p>
            </div>
          </div>
        );
      })}
      {events.length === 0 && (
        <div className="py-4 text-center text-[0.5rem] italic text-text-muted uppercase tracking-widest">
          No recent activity
        </div>
      )}
    </div>
  );
};
