import React from 'react';
import { Activity, Users, Flame, ChevronRight, AlertTriangle } from 'lucide-react';
import { SceneHealth } from '../types';

interface SceneHealthCardProps {
  health: SceneHealth;
  onClick: () => void;
}

export const SceneHealthCard: React.FC<SceneHealthCardProps> = ({ health, onClick }) => {
  const fpsColor = (fps: number) => {
    if (fps > 45) return 'text-success';
    if (fps >= 30) return 'text-warning';
    return 'text-danger';
  };

  const statusTone = health.avg_fps > 45 ? 'bg-success/5 border-success/30' : 
                     health.avg_fps >= 30 ? 'bg-warning/5 border-warning/30' : 
                     'bg-danger/5 border-danger/30';

  return (
    <button
      onClick={onClick}
      className={`group flex flex-col gap-3 border-2 p-4 text-left shadow-[2px_2px_0px_0px_black] transition-all hover:bg-accent/5 ${statusTone}`}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <Activity size={14} className="text-accent" />
            <span className="truncate text-xs font-black uppercase text-accent">{health.scene_id}</span>
          </div>
          {health.last_event && (
            <div className="flex items-center gap-1 text-[0.5rem] font-bold uppercase text-text-muted">
               <AlertTriangle size={10} className="text-warning" />
               {health.last_event}
            </div>
          )}
        </div>
        <div className="text-right">
          <div className={`text-xl font-black tracking-tighter ${fpsColor(health.avg_fps)}`}>
            {Math.round(health.avg_fps)}
          </div>
          <div className="text-[0.5rem] font-black uppercase text-text-muted">avg fps</div>
        </div>
      </div>

      <div className="grid grid-cols-3 gap-2 border-t border-black/10 pt-3">
        <div className="flex flex-col">
          <div className="flex items-center gap-1 text-[0.5rem] font-black uppercase text-text-muted">
            <Users size={10} />
            Live
          </div>
          <div className="text-[0.625rem] font-black">{health.active_players}</div>
        </div>
        <div className="flex flex-col">
          <div className="flex items-center gap-1 text-[0.5rem] font-black uppercase text-text-muted">
            <Flame size={10} />
            Hotzones
          </div>
          <div className="text-[0.625rem] font-black">{health.hotzone_count}</div>
        </div>
        <div className="flex flex-col">
          <div className="flex items-center gap-1 text-[0.5rem] font-black uppercase text-text-muted">
            Build
          </div>
          <div className="truncate text-[0.5rem] font-mono text-text-muted/70">{health.latest_build.slice(0, 7)}</div>
        </div>
      </div>

      <div className="mt-1 flex items-center justify-end gap-1 text-[0.5rem] font-black uppercase text-accent opacity-0 transition-opacity group-hover:opacity-100">
        Ver Detalle
        <ChevronRight size={10} />
      </div>
    </button>
  );
};
