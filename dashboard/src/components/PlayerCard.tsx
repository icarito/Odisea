import React, { useState } from 'react';
import type { Heartbeat } from '../types';
import { sendCommand } from '../api';
import { toast } from 'react-hot-toast';

interface PlayerCardProps {
  hb: Heartbeat;
  isActive: boolean;
  onClick: () => void;
  staleAge: number;
}

export const PlayerCard: React.FC<PlayerCardProps> = ({ hb, isActive, onClick, staleAge }) => {
  const [showReload, setShowReload] = useState(false);
  const [pckUrl, setPckUrl] = useState('');
  const [scenePath, setScenePath] = useState('');
  const [loading, setLoading] = useState(false);

  const handleReload = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (!pckUrl) {
      toast.error('PCK URL is required');
      return;
    }

    setLoading(true);
    try {
      const res = await sendCommand(hb.player_id, 'reload_pck', {
        url: pckUrl,
        scene: scenePath || undefined
      });
      if (res.ok) {
        toast.success('PCK reload command sent successfully');
        setShowReload(false);
      } else {
        toast.error(`Error: ${res.error || 'Unknown error'}`);
      }
    } catch (err: any) {
      toast.error(`Failed to send command: ${err.message}`);
    } finally {
      setLoading(false);
    }
  };

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

      <div className="mt-3 pt-3 border-t border-border-custom">
        <button
          onClick={(e) => { e.stopPropagation(); setShowReload(!showReload); }}
          className="w-full py-1 text-[10px] uppercase font-bold text-accent border border-accent/30 rounded hover:bg-accent/10 transition-colors"
        >
          {showReload ? 'Cancel' : 'Reload Scene'}
        </button>

        {showReload && (
          <div className="mt-2 flex flex-col gap-2" onClick={(e) => e.stopPropagation()}>
            <input
              type="text"
              placeholder="PCK URL"
              value={pckUrl}
              onChange={(e) => setPckUrl(e.target.value)}
              className="bg-bg-primary border border-border-custom text-[10px] px-2 py-1 rounded outline-none text-text-primary"
            />
            <input
              type="text"
              placeholder="Scene Path (optional)"
              value={scenePath}
              onChange={(e) => setScenePath(e.target.value)}
              className="bg-bg-primary border border-border-custom text-[10px] px-2 py-1 rounded outline-none text-text-primary"
            />
            <button
              onClick={handleReload}
              disabled={loading}
              className="py-1 bg-accent text-bg-primary text-[10px] uppercase font-bold rounded disabled:opacity-50"
            >
              {loading ? 'Sending...' : 'Confirm Reload'}
            </button>
          </div>
        )}
      </div>
    </div>
  );
};
