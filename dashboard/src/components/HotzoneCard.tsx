import React from 'react';
import { Flame, Play, Users } from 'lucide-react';

interface HotzoneCardProps {
  hotzone: any;
  onClick: () => void;
}

export const HotzoneCard: React.FC<HotzoneCardProps> = ({ hotzone, onClick }) => {
  return (
    <button
      onClick={onClick}
      className="group w-full border-2 border-black bg-bg-card p-3 text-left shadow-[2px_2px_0px_0px_black] hover:bg-black/5"
    >
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <div className="flex items-center gap-1.5 text-danger mb-1">
            <Flame size={12} fill="currentColor" />
            <span className="text-[0.625rem] font-black uppercase">{hotzone.scene || 'Unknown Scene'}</span>
          </div>
          <div className="text-[0.5rem] font-bold text-text-muted uppercase mb-2">
            Captured {new Date(hotzone.timestamp * 1000).toLocaleString()}
          </div>
          
          <div className="flex items-center gap-3">
            <div className="flex items-center gap-1">
              <Users size={10} className="text-text-muted" />
              <span className="text-[0.5625rem] font-black">2 affected</span>
            </div>
            <div className="text-[0.5625rem] font-black text-danger">AVG 18 FPS</div>
          </div>
        </div>

        <div className="shrink-0 border-2 border-success p-1.5 text-success group-hover:bg-success group-hover:text-black">
          <Play size={14} fill="currentColor" />
        </div>
      </div>
    </button>
  );
};
