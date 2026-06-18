import React, { useState } from 'react';
import { SceneVisual } from './SceneVisual';
import { SceneOverlayControls } from './SceneOverlayControls';
import { SceneHotzonesPanel } from './SceneHotzonesPanel';
import { SceneRecentTrajectories } from './SceneRecentTrajectories';
import { CockpitPanel } from './CockpitPanel';

interface SceneDetailProps {
  sceneId: string;
  players: any[];
  hotzones: any[];
  trajectories: any[];
  onBack: () => void;
}

export const SceneDetail: React.FC<SceneDetailProps> = ({
  sceneId,
  players,
  hotzones,
  trajectories,
  onBack
}) => {
  const [overlays, setOverlays] = useState({
    players: true,
    trajectories: true,
    hotzones: false
  });

  return (
    <div className="flex h-full flex-col">
      <div className="flex shrink-0 items-center justify-between border-b-4 border-black bg-bg-card px-4 py-2">
        <div className="flex items-center gap-4">
          <button onClick={onBack} className="text-[0.625rem] font-black uppercase hover:text-accent">← Back</button>
          <h2 className="text-sm font-black uppercase tracking-widest text-accent">{sceneId}</h2>
        </div>
        <SceneOverlayControls 
          active={overlays} 
          onChange={setOverlays} 
        />
      </div>

      <div className="grid flex-1 grid-cols-1 overflow-hidden lg:grid-cols-12">
        {/* Main Visual */}
        <div className="relative lg:col-span-8 border-r-2 border-black">
          <SceneVisual 
            sceneId={sceneId} 
            players={overlays.players ? players : []} 
            trajectories={overlays.trajectories ? trajectories : []}
            hotzones={overlays.hotzones ? hotzones : []}
          />
        </div>

        {/* Analytics Panels */}
        <div className="flex flex-col gap-4 overflow-y-auto p-4 lg:col-span-4 bg-bg-primary/30">
          <CockpitPanel title="Active Players" storageKey={`scene_players_${sceneId}`}>
             <div className="space-y-2">
               {players.map(p => (
                 <div key={p.player_id} className="flex items-center justify-between border-2 border-black bg-bg-card p-2 text-[0.625rem] font-black">
                    <div className="flex items-center gap-2">
                      <div className="h-2 w-2 rounded-full" style={{ backgroundColor: p.color }} />
                      {p.display_name || p.player_id.slice(0, 8)}
                    </div>
                    <span style={{ color: p.fps < 30 ? '#f85149' : p.fps < 45 ? '#d29922' : '#3fb950' }}>
                      {Math.round(p.fps)} FPS
                    </span>
                 </div>
               ))}
               {players.length === 0 && <div className="text-center text-[0.5rem] italic text-text-muted">No players in scene</div>}
             </div>
          </CockpitPanel>

          <CockpitPanel title="Hotzones" storageKey={`scene_hotzones_${sceneId}`}>
            <SceneHotzonesPanel hotzones={hotzones} />
          </CockpitPanel>

          <CockpitPanel title="Recent Trajectories" storageKey={`scene_trajectories_${sceneId}`}>
            <SceneRecentTrajectories trajectories={trajectories} />
          </CockpitPanel>
        </div>
      </div>
    </div>
  );
};
