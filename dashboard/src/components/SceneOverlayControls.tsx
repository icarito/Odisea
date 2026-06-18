import React from 'react';
import { Users, Map, Flame } from 'lucide-react';

interface SceneOverlayControlsProps {
  active: {
    players: boolean;
    trajectories: boolean;
    hotzones: boolean;
  };
  onChange: (state: any) => void;
}

export const SceneOverlayControls: React.FC<SceneOverlayControlsProps> = ({ active, onChange }) => {
  const toggle = (key: string) => {
    onChange({ ...active, [key]: !active[key] });
  };

  return (
    <div className="flex items-center gap-1 border-2 border-black bg-bg-primary p-0.5 shadow-[2px_2px_0px_0px_black]">
      <button
        onClick={() => toggle('players')}
        className={`p-1.5 transition-colors ${active.players ? 'bg-accent text-black' : 'text-text-muted hover:text-text-primary'}`}
        title="Toggle Players"
      >
        <Users size={14} />
      </button>
      <button
        onClick={() => toggle('trajectories')}
        className={`p-1.5 transition-colors ${active.trajectories ? 'bg-accent text-black' : 'text-text-muted hover:text-text-primary'}`}
        title="Toggle Trajectories"
      >
        <Map size={14} />
      </button>
      <button
        onClick={() => toggle('hotzones')}
        className={`p-1.5 transition-colors ${active.hotzones ? 'bg-accent text-black' : 'text-text-muted hover:text-text-primary'}`}
        title="Toggle Hotzones"
      >
        <Flame size={14} />
      </button>
    </div>
  );
};
