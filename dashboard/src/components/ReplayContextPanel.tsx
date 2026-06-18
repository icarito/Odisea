import React from 'react';

import { RetroButton } from './retro';
import { Tag, MapPin, Monitor } from 'lucide-react';

interface ReplayContextPanelProps {
  replay: any;
  onClose: () => void;
}

export const ReplayContextPanel: React.FC<ReplayContextPanelProps> = ({ replay, onClose }) => {
  if (!replay) return null;

  return (
    <div className="flex h-full flex-col bg-bg-card border-l-4 border-black">
      <div className="flex items-center justify-between border-b-2 border-black bg-bg-primary p-3">
        <h3 className="text-[0.625rem] font-black uppercase tracking-widest">Replay Context</h3>
        <button onClick={onClose} className="p-1 hover:bg-black/10">×</button>
      </div>

      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        <section className="space-y-3">
           <div className="flex items-center gap-2">
             <div className="h-4 w-4 bg-accent" />
             <span className="text-xs font-black uppercase">{replay.player_name || 'Anonymous'}</span>
           </div>

           <div className="grid grid-cols-1 gap-2">
             <div className="flex items-center gap-2 text-[0.5625rem] font-bold text-text-muted">
               <MapPin size={12} /> {replay.scene}
             </div>
             <div className="flex items-center gap-2 text-[0.5625rem] font-bold text-text-muted">
               <Monitor size={12} /> {replay.platform}
             </div>
           </div>
        </section>

        <section>
          <h4 className="text-[0.5rem] font-bold uppercase text-text-muted mb-2">Technical Context</h4>
          <div className="border-2 border-black bg-black/5 p-3 space-y-2 text-[0.625rem]">
            <div className="flex justify-between">
              <span className="font-bold text-text-muted">Build</span>
              <span className="font-mono">{replay.build_id || 'v1.2.3-abcd'}</span>
            </div>
            <div className="flex justify-between">
              <span className="font-bold text-text-muted">Avg FPS</span>
              <span className="font-black text-danger">24 FPS</span>
            </div>
          </div>
        </section>

        <section className="pt-4">
          <RetroButton variant="primary" className="w-full justify-start gap-2 text-[0.625rem]">
             <Tag size={12} /> EDIT ENTITY TAGS
          </RetroButton>
        </section>
      </div>
    </div>
  );
};
