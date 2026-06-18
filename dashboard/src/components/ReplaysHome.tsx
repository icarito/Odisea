import React from 'react';
import { HotzoneInbox } from './HotzoneInbox';
import { HistoricalTable } from './HistoricalTable';
// CollapsibleCard removed - unused

interface ReplaysHomeProps {
  hotzones: any[];
  sessions: any[];
  onPlay: (hzId: string) => void;
  onSelectSession: (session: any) => void;
}

export const ReplaysHome: React.FC<ReplaysHomeProps> = ({ 
  hotzones, 
  sessions, 
  onPlay,
  onSelectSession 
}) => {
  return (
    <div className="flex h-full flex-col p-4 gap-4 overflow-y-auto">
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-4">
        <div className="lg:col-span-4 flex flex-col gap-4">
          <h2 className="text-[0.625rem] font-black uppercase tracking-[0.3em] text-accent px-1">Hotzone Inbox</h2>
          <HotzoneInbox hotzones={hotzones} onPlay={onPlay} />
        </div>
        
        <div className="lg:col-span-8 flex flex-col gap-4">
          <h2 className="text-[0.625rem] font-black uppercase tracking-[0.3em] text-text-muted px-1">Recent Sessions</h2>
          <div className="border-2 border-black bg-bg-card shadow-retro">
            <HistoricalTable 
              sessions={sessions} 
              onSelectSession={onSelectSession} 
            />
          </div>
        </div>
      </div>
    </div>
  );
};
