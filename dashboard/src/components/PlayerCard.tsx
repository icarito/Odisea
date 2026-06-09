import React from 'react';
import type { Heartbeat } from '../types';

interface PlayerCardProps {
  hb: Heartbeat;
  isActive: boolean;
  onClick: () => void;
}

export const PlayerCard: React.FC<PlayerCardProps> = ({ hb, isActive, onClick }) => {
  const p = hb.player;
  const age = Date.now() / 1000 - hb.timestamp;

  let statusColor = 'bg-success';
  if (age > 30) statusColor = 'bg-danger';
  else if (age > 10) statusColor = 'bg-warning';

  return (
    <div
      className={`p-3 bg-bg-card border ${isActive ? 'border-accent' : 'border-border-custom'} rounded cursor-pointer hover:bg-[#1c2129] transition-colors`}
      onClick={onClick}
    >
      <div className="flex justify-between items-center mb-2">
        <div className="flex items-center gap-2">
          <div className={`w-2 h-2 rounded-full ${statusColor}`} />
          <span className="font-bold text-accent">{hb.player_id.slice(0, 8)}</span>
        </div>
        <span className="text-[10px] text-text-muted uppercase">{hb.platform} · {hb.host}</span>
      </div>

      <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
        <div className="text-text-muted">Scene</div>
        <div className="text-right truncate">{p.scene}</div>

        <div className="text-text-muted">Mode</div>
        <div className="text-right">{p.mode}</div>

        <div className="text-text-muted">FPS</div>
        <div className="text-right">{Math.round(p.fps)}</div>

        <div className="text-text-muted">Mem</div>
        <div className="text-right">{(p.memory_mb ?? 0).toFixed(1)} MB</div>

        <div className="text-text-muted">Tick</div>
        <div className="text-right">{p.tick}</div>
      </div>
    </div>
  );
};
