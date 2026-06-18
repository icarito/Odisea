import React from 'react';
import { PlayerHealthCard } from './PlayerHealthCard';
import { X, Clock, Tag as TagIcon, PlayCircle } from 'lucide-react';
import { RetroButton } from './retro';

interface PlayerDetailPanelProps {
  player: any;
  history: any[];
  onClose: () => void;
  onTag: () => void;
  onViewHistory: () => void;
  onReplay: () => void;
}

export const PlayerDetailPanel: React.FC<PlayerDetailPanelProps> = ({ 
  player, 
  history, 
  onClose,
  onTag,
  onViewHistory: onHistory,
  onReplay
}) => {
  if (!player) return null;

  return (
    <div className="flex h-full flex-col bg-bg-card shadow-retro border-l-4 border-black">
      <div className="flex items-center justify-between border-b-2 border-black bg-bg-primary p-3">
        <div className="flex items-center gap-2 min-w-0">
          <div className="h-3 w-3 rounded-full" style={{ backgroundColor: player.color || '#fff' }} />
          <h3 className="truncate text-xs font-black uppercase tracking-widest">{player.display_name || player.player_id.slice(0, 12)}</h3>
        </div>
        <button onClick={onClose} className="p-1 hover:bg-black/10 transition-colors">
          <X size={16} />
        </button>
      </div>

      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {/* Primary Health */}
        <section>
          <h4 className="mb-2 text-[0.5rem] font-bold uppercase tracking-[0.2em] text-text-muted">Current Health</h4>
          <PlayerHealthCard 
            fps={player.fps || 0} 
            history={history} 
            platform={player.platform || 'unknown'} 
          />
        </section>

        {/* Technical Context */}
        <section className="grid grid-cols-2 gap-3 border-2 border-black/10 bg-black/5 p-3">
          <div className="flex flex-col">
            <span className="text-[0.5rem] font-bold uppercase text-text-muted">Scene</span>
            <span className="truncate text-[0.625rem] font-black">{player.scene}</span>
          </div>
          <div className="flex flex-col">
            <span className="text-[0.5rem] font-bold uppercase text-text-muted">Platform</span>
            <span className="truncate text-[0.625rem] font-black">{player.platform}</span>
          </div>
          <div className="flex flex-col">
            <span className="text-[0.5rem] font-bold uppercase text-text-muted">Memory</span>
            <span className="truncate text-[0.625rem] font-black">{Math.round(player.memory_mb || 0)} MB</span>
          </div>
          <div className="flex flex-col">
            <span className="text-[0.5rem] font-bold uppercase text-text-muted">Pos</span>
            <span className="truncate text-[0.625rem] font-black font-mono text-accent">
              {Math.round(player.pos_x)}, {Math.round(player.pos_z)}
            </span>
          </div>
        </section>

        {/* Actions */}
        <section className="flex flex-col gap-2 pt-2">
          <RetroButton variant="primary" onClick={onTag} className="w-full justify-start gap-2 text-[0.625rem]">
            <TagIcon size={12} /> TAGS & NOTES
          </RetroButton>
          <RetroButton variant="secondary" onClick={onHistory} className="w-full justify-start gap-2 text-[0.625rem]">
            <Clock size={12} /> FULL HISTORY
          </RetroButton>
          <RetroButton variant="secondary" onClick={onReplay} className="w-full justify-start gap-2 text-[0.625rem]">
            <PlayCircle size={12} /> OPEN REPLAY
          </RetroButton>
        </section>
      </div>
    </div>
  );
};
