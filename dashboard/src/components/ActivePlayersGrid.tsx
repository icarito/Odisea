import React from 'react';
import { PlayerCard } from './PlayerCard';

interface ActivePlayersGridProps {
  players: any[];
  onPlayerClick: (playerId: string) => void;
  onSceneClick: (scene: string) => void;
}

export const ActivePlayersGrid: React.FC<ActivePlayersGridProps> = ({ 
  players, 
  onPlayerClick,
  onSceneClick 
}) => {
  const playersByScene = players.reduce((acc: Record<string, any[]>, player) => {
    const scene = player.scene || 'Unknown';
    if (!acc[scene]) acc[scene] = [];
    acc[scene].push(player);
    return acc;
  }, {});

  const scenes = Object.keys(playersByScene).sort();

  if (players.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-12 text-center opacity-40">
        <div className="mb-2 h-1 w-12 bg-text-muted" />
        <span className="text-[0.625rem] font-black uppercase tracking-widest text-text-muted">
          No players active
        </span>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      {scenes.map(scene => (
        <div key={scene} className="flex flex-col gap-2">
          <button 
            onClick={() => onSceneClick(scene)}
            className="flex items-center gap-2 group w-full text-left"
          >
            <span className="text-[0.625rem] font-black uppercase tracking-widest text-accent group-hover:underline">
              {scene}
            </span>
            <div className="h-[2px] flex-1 bg-black/10 group-hover:bg-accent/30" />
            <span className="text-[0.625rem] font-black text-text-muted">
              {playersByScene[scene].length}
            </span>
          </button>
          
          <div className="grid grid-cols-1 gap-2">
            {playersByScene[scene].map(player => {
              const staleAge = player.last_seen ? (Date.now() - player.last_seen * 1000) / 1000 : 0;
              return (
                <PlayerCard 
                  key={player.player_id}
                  hb={player} 
                  isActive={false} 
                  onClick={() => onPlayerClick(player.player_id)}
                  staleAge={staleAge}
                />
              );
            })}
          </div>
        </div>
      ))}
    </div>
  );
};
