import React from 'react';
import { Flame } from 'lucide-react';

interface HotzoneOverlayProps {
  hotzones: any[];
  onSelect: (hz: any) => void;
}

export const HotzoneOverlay: React.FC<HotzoneOverlayProps> = ({ hotzones, onSelect }) => {
  return (
    <>
      {hotzones.map((hz) => (
        <button
          key={hz.id}
          onClick={() => onSelect(hz)}
          className="absolute h-8 w-8 -translate-x-1/2 -translate-y-1/2 flex items-center justify-center rounded-full bg-danger/20 border-2 border-danger text-danger hover:bg-danger hover:text-white transition-all animate-pulse"
          style={{ 
            left: `${50 + (hz.pos_x / 100) * 40}%`, 
            top: `${50 + (hz.pos_z / 100) * 40}%`,
          }}
        >
          <Flame size={16} fill="currentColor" />
        </button>
      ))}
    </>
  );
};
