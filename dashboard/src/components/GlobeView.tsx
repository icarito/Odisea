import React from 'react';
import { Globe3D } from './Globe3D/Globe3D';
import type { GeoPlayer } from '../types';

interface GlobeViewProps {
  players: GeoPlayer[];
  onSelectPlayer?: (playerId: string) => void;
}

export const GlobeView: React.FC<GlobeViewProps> = ({ players, onSelectPlayer }) => {
  return (
    <div className="h-full w-full bg-[#0d1117] flex flex-col p-4">
      <div className="mb-4 flex items-center justify-between shrink-0">
        <div>
          <h2 className="text-xl font-black italic text-accent uppercase tracking-tighter">Mapa Global 3D</h2>
          <p className="text-[0.625rem] text-text-muted uppercase">Distribución geográfica de jugadores</p>
        </div>
        <div className="flex gap-4 text-[0.625rem] font-bold uppercase">
          <div className="flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full bg-success" /> Conectado
          </div>
          <div className="flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full bg-warning" /> Última hora
          </div>
          <div className="flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full bg-text-muted" /> {'>'}1h
          </div>
        </div>
      </div>

      <div className="flex-1 border-4 border-black bg-black/40 relative overflow-hidden min-h-0">
        <Globe3D players={players} onSelectPlayer={onSelectPlayer} />
      </div>
    </div>
  );
};
