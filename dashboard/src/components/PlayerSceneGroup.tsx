import React from 'react';

interface PlayerSceneGroupProps {
  scene: string;
  players: any[];
  onSelectPlayer: (id: string) => void;
  selectedPlayerId?: string | null;
}

export const PlayerSceneGroup: React.FC<PlayerSceneGroupProps> = ({ 
  scene, 
  players, 
  onSelectPlayer,
  selectedPlayerId
}) => {
  // Sort players by urgency (lower FPS first)
  const sortedPlayers = [...players].sort((a, b) => (a.fps || 60) - (b.fps || 60));

  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center gap-2 px-1">
        <span className="text-[0.625rem] font-black uppercase tracking-widest text-accent">{scene}</span>
        <div className="h-px flex-1 bg-black/10" />
        <span className="text-[0.5rem] font-bold text-text-muted">{players.length}</span>
      </div>
      <div className="grid grid-cols-1 gap-2">
        {sortedPlayers.map(player => (
          <div 
            key={player.player_id}
            onClick={() => onSelectPlayer(player.player_id)}
            className={`cursor-pointer transition-transform hover:scale-[1.01] active:scale-[0.99] ${
              selectedPlayerId === player.player_id ? 'ring-2 ring-accent ring-offset-2 ring-offset-bg-primary' : ''
            }`}
          >
            {/* We might need to extend PlayerCard or use a new variant */}
            <div className="border-2 border-black bg-bg-card p-3 cursor-pointer hover:bg-accent/10" onClick={() => onSelectPlayer && onSelectPlayer(player.player_id)}>
              <span className="text-[0.625rem] font-black">{player.display_name || player.player_id.slice(0, 8)}</span>
              <span className="ml-2 text-[0.5rem] text-text-muted">{player.scene}</span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};
