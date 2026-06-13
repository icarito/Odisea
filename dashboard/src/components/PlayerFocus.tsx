import React from 'react';
import { RetroButton } from './retro';
import { User, Tag, X } from 'lucide-react';

interface PlayerFocusProps {
  playerId: string;
  displayName?: string | null;
  onClear: () => void;
  onTagClick: () => void;
}

export const PlayerFocus: React.FC<PlayerFocusProps> = ({ playerId, displayName, onClear, onTagClick }) => {
  return (
    <div className="flex items-center gap-2 bg-accent/10 border-2 border-accent/40 p-1.5 rounded-sm">
      <div className="flex items-center gap-1.5">
        <User size={14} className="text-accent" />
        <span className="text-[0.625rem] font-black uppercase text-accent truncate max-w-[120px]">
          Focussing: {displayName || playerId}
        </span>
      </div>
      <div className="flex gap-1 ml-auto">
        <RetroButton 
            variant="primary" 
            onClick={onTagClick} 
            className="py-0.5 px-2 text-[0.5rem] h-auto flex items-center gap-1"
        >
          <Tag size={10} /> Tag
        </RetroButton>
        <button 
            onClick={onClear} 
            className="p-1 hover:text-danger text-text-muted"
            title="Clear focus"
        >
          <X size={14} />
        </button>
      </div>
    </div>
  );
};
