import React from 'react';
import { RetroBadge } from './retro';

interface PlayerCardProps {
  hb: any;
  isActive: boolean;
  onClick: () => void;
  staleAge: number;
}

export const PlayerCard: React.FC<PlayerCardProps> = ({ hb, isActive, onClick, staleAge }) => {
  const p = hb.player || {};
  const isStale = staleAge > 5;
  const fps = p.fps || 0;
  
  const getFpsColor = (f: number) => {
    if (f > 45) return 'success';
    if (f > 30) return 'warning';
    return 'danger';
  };

  return (
    <div
      onClick={onClick}
      className={`
        @container relative p-3 cursor-pointer border-4 transition-all duration-75 select-none
        ${isActive 
          ? 'bg-bg-card border-accent shadow-[4px_4px_0px_0px_rgba(127,209,255,0.4)]' 
          : 'bg-bg-primary border-black hover:border-text-muted hover:shadow-[4px_4px_0px_0px_rgba(0,0,0,0.5)]'
        }
        ${isStale ? 'opacity-50 grayscale' : ''}
      `}
    >
      <div className="flex flex-col @[200px]:flex-row @[200px]:justify-between @[200px]:items-start mb-2">
        <div className="flex flex-col">
          <span className={`text-[0.625rem] font-black uppercase tracking-tighter ${isActive ? 'text-accent' : 'text-text-muted'}`}>
            Subject ID
          </span>
          <span className="text-xs font-bold truncate max-w-[120px]">
            {hb.player_id}
          </span>
        </div>
        <RetroBadge color={getFpsColor(fps)} className="scale-90 origin-left @[200px]:origin-right mt-1 @[200px]:mt-0 self-start @[200px]:self-auto">
          {fps} FPS
        </RetroBadge>
      </div>

      <div className="grid grid-cols-2 gap-2 mt-1">
        <div className="flex flex-col">
          <span className="text-[0.5rem] text-text-muted uppercase">Scene</span>
          <span className="text-[0.5625rem] truncate text-accent">{p.scene || 'unknown'}</span>
        </div>
        <div className="flex flex-col text-right">
          <span className="text-[0.5rem] text-text-muted uppercase">Latency</span>
          <span className="text-[0.5625rem] font-mono">{staleAge.toFixed(1)}s</span>
        </div>
      </div>

      {isActive && (
          <div className="absolute -left-1 top-1/2 -translate-y-1/2 w-1 h-6 bg-accent" />
      )}
    </div>
  );
};
