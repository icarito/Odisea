import React from 'react';
import { Users, Flame, AlertTriangle } from 'lucide-react';

interface SceneHealthCardProps {
  scene: any;
  onClick: () => void;
}

export const SceneHealthCard: React.FC<SceneHealthCardProps> = ({ scene, onClick }) => {
  const statusColor = scene.avg_fps > 45 ? 'border-success' : scene.avg_fps > 30 ? 'border-warning' : 'border-danger';
  const fpsColor = scene.avg_fps > 45 ? 'text-success' : scene.avg_fps > 30 ? 'text-warning' : 'text-danger';

  return (
    <button
      onClick={onClick}
      className={`group flex flex-col border-2 border-black bg-bg-card text-left shadow-[4px_4px_0px_0px_black] transition-transform hover:-translate-y-0.5 active:translate-y-0 ${statusColor}`}
    >
      <div className="border-b-2 border-black bg-bg-primary p-2 group-hover:bg-black/5">
        <h3 className="truncate text-xs font-black uppercase tracking-widest text-accent">{scene.scene_id}</h3>
      </div>
      
      <div className="flex-1 p-3">
        <div className="mb-4 flex items-baseline justify-between">
          <div className="flex flex-col">
            <span className={`text-2xl font-black ${fpsColor}`}>{scene.avg_fps.toFixed(0)}</span>
            <span className="text-[0.5rem] font-bold uppercase text-text-muted">Avg FPS</span>
          </div>
          <div className="text-right flex flex-col">
             <span className="text-sm font-black text-text-primary">{scene.min_fps.toFixed(0)}</span>
             <span className="text-[0.5rem] font-bold uppercase text-text-muted">Min FPS</span>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-2 border-t-2 border-black/5 pt-3">
          <div className="flex items-center gap-1.5">
            <Users size={12} className="text-text-muted" />
            <span className="text-[0.625rem] font-black">{scene.active_players} <span className="font-bold text-text-muted">Active</span></span>
          </div>
          <div className="flex items-center gap-1.5">
            <Flame size={12} className={scene.hotzone_count > 0 ? 'text-danger' : 'text-text-muted'} />
            <span className="text-[0.625rem] font-black">{scene.hotzone_count} <span className="font-bold text-text-muted">Hotzones</span></span>
          </div>
        </div>
      </div>

      {scene.hotzone_count > 5 && (
        <div className="bg-danger/10 px-2 py-1 flex items-center gap-1.5">
          <AlertTriangle size={10} className="text-danger" />
          <span className="text-[0.5rem] font-black uppercase text-danger">High Friction Area</span>
        </div>
      )}
    </button>
  );
};
