import React from 'react';
import { Flame } from 'lucide-react';

interface SceneHotzonesPanelProps {
  hotzones: any[];
}

export const SceneHotzonesPanel: React.FC<SceneHotzonesPanelProps> = ({ hotzones }) => {
  return (
    <div className="flex flex-col gap-2">
      {hotzones.map((hz, idx) => (
        <div key={idx} className="border-2 border-black bg-bg-card p-2 shadow-[2px_2px_0px_0px_black]">
          <div className="flex items-center justify-between mb-1">
            <div className="flex items-center gap-1.5 text-danger">
              <Flame size={12} />
              <span className="text-[0.625rem] font-black uppercase tracking-widest">Hotzone #{idx + 1}</span>
            </div>
            <span className="text-[0.5rem] font-bold text-text-muted">
              {new Date(hz.timestamp * 1000).toLocaleDateString()}
            </span>
          </div>
          <div className="grid grid-cols-2 gap-2 text-[0.5625rem]">
            <div className="flex flex-col">
              <span className="text-text-muted uppercase font-bold">Severity</span>
              <span className="font-black text-danger">CRITICAL (22 FPS)</span>
            </div>
            <div className="flex flex-col">
              <span className="text-text-muted uppercase font-bold">Affected</span>
              <span className="font-black">3 Players</span>
            </div>
          </div>
        </div>
      ))}
      {hotzones.length === 0 && (
        <div className="py-4 text-center text-[0.5rem] italic text-text-muted uppercase tracking-widest">
          No hotzones detected
        </div>
      )}
    </div>
  );
};
