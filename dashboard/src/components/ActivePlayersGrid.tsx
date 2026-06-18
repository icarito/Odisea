import React from 'react';
import { PlayerSceneGroup } from './PlayerSceneGroup';

interface ActivePlayersGridProps {
  players: any[];
  onSelectPlayer: (id: string) => void;
  selectedPlayerId?: string | null;
}

export const ActivePlayersGrid: React.FC<ActivePlayersGridProps> = ({ 
  players, 
  onSelectPlayer,
  selectedPlayerId 
}) => {
  const playersByScene = players.reduce((acc, p) => {
    const scene = p.scene || 'Unknown';
    if (!acc[scene]) acc[scene] = [];
    acc[scene].push(p);
    return acc;
  }, {} as Record<string, any[]>);

  // Sort scenes by "urgency" (critical FPS first) then by name
  const sortedScenes = Object.keys(playersByScene).sort((a, b) => {
    const getMaxUrgency = (pList: any[]) => Math.min(...pList.map(p => p.fps || 60));
    return getMaxUrgency(playersByScene[a]) - getMaxUrgency(playersByScene[b]);
  });

  return (
    <div className="flex flex-col gap-4">
      {sortedScenes.map(scene => (
        <PlayerSceneGroup 
          key={scene} 
          scene={scene} 
          players={playersByScene[scene]} 
          onSelectPlayer={onSelectPlayer}
          selectedPlayerId={selectedPlayerId}
        />
      ))}
      {players.length === 0 && (
        <div className="py-8 text-center text-xs italic text-text-muted">
          No hay jugadores activos
        </div>
      )}
    </div>
  );
};
