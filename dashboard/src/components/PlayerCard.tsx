import React from 'react';
import type { Heartbeat } from '../types';

interface PlayerCardProps {
  hb: Heartbeat;
  isActive: boolean;
  onClick: () => void;
  staleAge: number;
}

export const PlayerCard: React.FC<PlayerCardProps> = ({ hb, isActive, onClick, staleAge }) => {
  const p = hb.player;

  let statusColor = 'bg-warning';
  let opacityStyle: React.CSSProperties = {};
  if (staleAge > 2) {
    statusColor = 'bg-danger';
    opacityStyle = { opacity: 0.3 };
  } else if (staleAge <= 2) {
    statusColor = 'bg-success';
  }

  return (
    <div
      className={`p-3 bg-bg-card border ${isActive ? 'border-accent' : 'border-border-custom'} rounded cursor-pointer hover:bg-[#1c2129] transition-colors`}
      onClick={onClick}
      style={opacityStyle}
    >
      <div className="flex justify-between items-center mb-2">
        <div className="flex items-center gap-2">
          <div className={`w-2 h-2 rounded-full ${statusColor}`} />
          <span className="font-bold text-accent">{hb.player_id.slice(0, 8)}</span>
        </div>
        <span className="text-[10px] text-text-muted uppercase">{hb.platform ?? "?"} · {hb.host ?? "?"}</span>
      </div>

      <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
        <div className="text-text-muted">Scene</div>
        <div className="text-right truncate">{p.scene || "N/A"}</div>

        <div className="text-text-muted">Mode</div>
        <div className="text-right">{p.mode || "N/A"}</div>

        <div className="text-text-muted">FPS</div>
        <div className="text-right">{typeof p.fps === 'number' ? Math.round(p.fps) : "N/A"}</div>

        <div className="text-text-muted">DC</div>
        <div className="text-right">{p.perf?.dc ?? "N/A"}</div>

        <div className="text-text-muted">Mem</div>
        <div className="text-right">{typeof p.memory_mb === 'number' ? p.memory_mb.toFixed(1) + " MB" : "N/A"}</div>

        <div className="text-text-muted">Tick</div>
        <div className="text-right">{p.tick ?? "N/A"}</div>
      </div>
    </div>
  );
};
