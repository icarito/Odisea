import React from 'react';
import { HotzoneCard } from './HotzoneCard';

interface HotzoneInboxProps {
  hotzones: any[];
  onPlay: (id: string) => void;
}

export const HotzoneInbox: React.FC<HotzoneInboxProps> = ({ hotzones, onPlay }) => {
  return (
    <div className="flex flex-col gap-2">
      {hotzones.map((hz) => (
        <HotzoneCard 
          key={hz.id} 
          hotzone={hz} 
          onClick={() => onPlay(hz.id)} 
        />
      ))}
      {hotzones.length === 0 && (
        <div className="py-12 border-2 border-dashed border-black/10 rounded-lg text-center">
          <p className="text-[0.5rem] font-bold uppercase tracking-widest text-text-muted">No new hotzones</p>
        </div>
      )}
    </div>
  );
};
