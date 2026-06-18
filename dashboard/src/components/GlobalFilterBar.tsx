import React from 'react';
import { X, Plus, Flame } from 'lucide-react';
import { PLATFORM_META } from './PlatformFilter';

interface GlobalFilterBarProps {
  selectedScene: string;
  selectedPlatforms: Set<string>;
  selectedCountry: string;
  warmupSeconds: number;
  onRemoveScene: () => void;
  onTogglePlatform: (platform: string) => void;
  onRemoveCountry: () => void;
  onToggleWarmup: () => void;
  onOpenFilters: () => void;
  allPlatforms: string[];
}

export const GlobalFilterBar: React.FC<GlobalFilterBarProps> = ({
  selectedScene,
  selectedPlatforms,
  selectedCountry,
  warmupSeconds,
  onRemoveScene,
  onTogglePlatform,
  onRemoveCountry,
  onToggleWarmup,
  onOpenFilters,
  allPlatforms,
}) => {
  const isAllPlatforms = selectedPlatforms.size === allPlatforms.filter(p => p !== 'server').length;
  
  return (
    <div className="flex items-center gap-2 border-b-2 border-black bg-bg-card px-3 py-1.5 overflow-x-auto no-scrollbar">
      <div className="flex items-center gap-1.5 whitespace-nowrap">
        {selectedScene !== 'all' && (
          <FilterChip label={`Escena: ${selectedScene}`} onRemove={onRemoveScene} />
        )}
        
        {!isAllPlatforms && Array.from(selectedPlatforms).map(p => (
          <FilterChip 
            key={p} 
            label={PLATFORM_META[p]?.label || p} 
            onRemove={() => onTogglePlatform(p)} 
            icon={PLATFORM_META[p]?.icon}
          />
        ))}

        {selectedCountry !== 'all' && (
          <FilterChip label={`País: ${selectedCountry}`} onRemove={onRemoveCountry} />
        )}

        {warmupSeconds > 0 && (
          <FilterChip 
            label={`Warmup: ${warmupSeconds}s`} 
            onRemove={onToggleWarmup} 
            icon={<Flame size={12} className="text-warning" />}
          />
        )}

        <button
          onClick={onOpenFilters}
          className="flex items-center gap-1 border-2 border-dashed border-black/30 px-2 py-1 text-[0.625rem] font-black uppercase text-text-muted hover:border-accent hover:text-accent transition-colors"
        >
          <Plus size={12} />
          <span>Añadir filtro</span>
        </button>
      </div>
    </div>
  );
};

const FilterChip: React.FC<{ label: string; onRemove: () => void; icon?: React.ReactNode }> = ({ label, onRemove, icon }) => (
  <div className="flex items-center gap-1.5 border-2 border-black bg-bg-primary px-2 py-1 text-[0.625rem] font-black uppercase shadow-[1px_1px_0px_0px_black]">
    {icon}
    <span>{label}</span>
    <button onClick={onRemove} className="text-text-muted hover:text-danger">
      <X size={12} />
    </button>
  </div>
);
