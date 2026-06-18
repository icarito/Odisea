import React from 'react';

interface SceneVisualProps {
  sceneId: string;
  players: any[];
  trajectories: any[];
  hotzones: any[];
}

export const SceneVisual: React.FC<SceneVisualProps> = ({
  sceneId,
  players,
  trajectories,
  hotzones
}) => {
  // This would typically be a Canvas/WebGL view. 
  // For now, we'll placeholder it with a styled container.
  return (
    <div className="h-full w-full bg-black/60 flex items-center justify-center">
      <div className="text-center">
        <div className="text-[0.625rem] font-black uppercase tracking-[0.5em] text-accent/50 mb-2">3D Analytic View</div>
        <div className="text-2xl font-black text-white/20 uppercase">{sceneId}</div>
        <div className="mt-4 flex gap-8 justify-center">
          <div className="text-[0.5rem] font-bold text-text-muted uppercase">Players: {players.length}</div>
          <div className="text-[0.5rem] font-bold text-text-muted uppercase">Hotzones: {hotzones.length}</div>
          <div className="text-[0.5rem] font-bold text-text-muted uppercase">Traces: {trajectories.length}</div>
        </div>
      </div>
      
      {/* Simulation of overlays */}
      <div className="absolute inset-0 pointer-events-none">
        {players.map(p => (
          <div 
            key={p.player_id}
            className="absolute h-2 w-2 rounded-full border border-white shadow-[0_0_10px_white]"
            style={{ 
              left: `${50 + (p.pos_x / 100) * 40}%`, 
              top: `${50 + (p.pos_z / 100) * 40}%`,
              backgroundColor: p.color 
            }}
          />
        ))}
      </div>
    </div>
  );
};
