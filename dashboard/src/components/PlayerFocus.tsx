import React from 'react';
import { RetroButton } from './retro';
import { User, Tag, X } from 'lucide-react';

interface PlayerFocusProps {
  playerId: string;
  displayName?: string | null;
  country?: string | null;
  countryCode?: string | null;
  onClear: () => void;
  onTagClick: () => void;
}

const flagEmoji = (countryCode?: string | null): string => {
  const code = (countryCode || '').trim().toUpperCase();
  if (!/^[A-Z]{2}$/.test(code)) return '';
  return Array.from(code).map((char) => String.fromCodePoint(char.charCodeAt(0) + 127397)).join('');
};

export const PlayerFocus: React.FC<PlayerFocusProps> = ({ playerId, displayName, country, countryCode, onClear, onTagClick }) => {
  const label = displayName || playerId.slice(0, 12);
  const flag = flagEmoji(countryCode);
  const place = [flag, countryCode || country].filter(Boolean).join(' ');

  return (
    <div className="flex max-w-[72vw] items-center gap-2 border-2 border-accent/50 bg-bg-primary/95 p-1.5 shadow-[3px_3px_0px_0px_black] backdrop-blur-sm sm:max-w-[360px]">
      <div className="flex min-w-0 items-center gap-1.5">
        <User size={14} className="shrink-0 text-accent" />
        <div className="min-w-0 leading-tight">
          <div className="truncate text-[0.625rem] font-black uppercase text-accent">{label}</div>
          <div className="truncate text-[0.5rem] text-text-muted">
            {place ? `${place} · ${playerId.slice(0, 10)}` : playerId.slice(0, 14)}
          </div>
        </div>
      </div>
      <div className="ml-auto flex shrink-0 gap-1">
        <RetroButton 
            variant="primary" 
            onClick={onTagClick} 
            className="flex h-auto items-center gap-1 px-2 py-0.5 text-[0.5rem]"
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
