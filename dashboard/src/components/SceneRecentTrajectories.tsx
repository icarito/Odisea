import React from 'react';
import { Map } from 'lucide-react';

interface SceneRecentTrajectoriesProps {
  trajectories: any[];
}

export const SceneRecentTrajectories: React.FC<SceneRecentTrajectoriesProps> = ({ trajectories }) => {
  return (
    <div className="flex flex-col gap-2">
      {trajectories.map((trace, idx) => (
        <div key={idx} className="flex items-center gap-3 border-2 border-black bg-bg-card p-2 shadow-[2px_2px_0px_0px_black]">
          <div className="text-accent">
            <Map size={14} />
          </div>
          <div className="flex-1 min-w-0">
            <div className="flex justify-between items-baseline">
              <span className="text-[0.625rem] font-black uppercase truncate">{trace.player_id.slice(0, 8)}</span>
              <span className="text-[0.5rem] font-bold text-text-muted">{trace.duration}s</span>
            </div>
            <div className="h-1 bg-black/10 mt-1">
               <div className="h-full bg-accent/40" style={{ width: `${Math.min(100, trace.points / 2)}%` }} />
            </div>
          </div>
        </div>
      ))}
      {trajectories.length === 0 && (
        <div className="py-4 text-center text-[0.5rem] italic text-text-muted uppercase tracking-widest">
          No recent trajectories
        </div>
      )}
    </div>
  );
};
