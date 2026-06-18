import React from 'react';
import { X, Flame } from 'lucide-react';

interface FilterChipProps {
  label: string;
  value: string;
  onRemove: () => void;
}

const FilterChip: React.FC<FilterChipProps> = ({ label, value, onRemove }) => (
  <div className="flex items-center gap-1.5 border-2 border-black bg-bg-card px-2 py-1 shadow-[2px_2px_0px_0px_black]">
    <span className="text-[0.625rem] font-bold uppercase text-text-muted">{label}:</span>
    <span className="text-[0.625rem] font-black uppercase text-accent">{value}</span>
    <button
      onClick={onRemove}
      className="ml-1 rounded-full p-0.5 hover:bg-black/10 hover:text-danger"
    >
      <X size={10} />
    </button>
  </div>
);

interface GlobalFilterBarProps {
  filters: {
    scene: string;
    platform: Set<string>;
    country: string;
    warmup: number;
  };
  onRemoveFilter: (type: string, value?: string) => void;
}

export const GlobalFilterBar: React.FC<GlobalFilterBarProps> = ({ filters, onRemoveFilter }) => {
  const hasActiveFilters = 
    filters.scene !== 'all' || 
    filters.platform.size < 5 || // Assuming 5 is total known
    filters.country !== 'all' ||
    filters.warmup > 0;

  if (!hasActiveFilters && filters.warmup === 0) return null;

  return (
    <div className="flex flex-wrap items-center gap-2 border-b-2 border-black/10 bg-bg-primary/50 px-4 py-2">
      {filters.scene !== 'all' && (
        <FilterChip 
          label="Escena" 
          value={filters.scene} 
          onRemove={() => onRemoveFilter('scene')} 
        />
      )}
      
      {Array.from(filters.platform).map(p => (
        <FilterChip 
          key={p}
          label="Plataforma" 
          value={p} 
          onRemove={() => onRemoveFilter('platform', p)} 
        />
      ))}

      {filters.country !== 'all' && (
        <FilterChip 
          label="País" 
          value={filters.country} 
          onRemove={() => onRemoveFilter('country')} 
        />
      )}

      {filters.warmup > 0 && (
        <div className="flex items-center gap-1.5 border-2 border-black bg-accent px-2 py-1 text-black shadow-[2px_2px_0px_0px_black]">
          <Flame size={10} fill="black" />
          <span className="text-[0.625rem] font-black uppercase">Warmup: {filters.warmup}s</span>
          <button
            onClick={() => onRemoveFilter('warmup')}
            className="ml-1 rounded-full p-0.5 hover:bg-black/20"
          >
            <X size={10} />
          </button>
        </div>
      )}
    </div>
  );
};
