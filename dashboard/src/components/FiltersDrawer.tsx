import React from 'react';
import { X } from 'lucide-react';
import { RetroSelect } from './retro';
import { PLATFORM_META } from './PlatformFilter';

const KNOWN_ORDER = ['server', 'android', 'linux', 'windows', 'macos', 'web'];

interface FiltersDrawerProps {
  open: boolean;
  onClose: () => void;
  platforms: string[];
  selectedPlatforms: Set<string>;
  onTogglePlatform: (platform: string) => void;
  scenes: string[];
  selectedScene: string;
  onSelectScene: (scene: string) => void;
  onReset: () => void;
}

// Slide-in side drawer (right) holding the platform + scene filters that used to
// live cramped in the header. Opened from the header "Filtros" button. Reuses
// the overlay/slide pattern of PlayerBottomSheet but anchored to the side.
export const FiltersDrawer: React.FC<FiltersDrawerProps> = ({
  open, onClose, platforms, selectedPlatforms, onTogglePlatform,
  scenes, selectedScene, onSelectScene, onReset,
}) => {
  const visiblePlatforms = KNOWN_ORDER.filter((p) => platforms.includes(p));

  return (
    <div
      className={`fixed inset-0 z-[9000] ${open ? '' : 'pointer-events-none'}`}
      aria-hidden={!open}
    >
      {/* Scrim */}
      <div
        className={`absolute inset-0 bg-black/70 transition-opacity duration-200 ${open ? 'opacity-100' : 'opacity-0'}`}
        onClick={onClose}
      />
      {/* Panel */}
      <div
        className={`absolute right-0 top-0 h-full w-72 max-w-[85vw] border-l-4 border-black bg-bg-card shadow-[-4px_0_0_0_black] transition-transform duration-200 ${open ? 'translate-x-0' : 'translate-x-full'} flex flex-col`}
      >
        <div className="flex items-center justify-between border-b-4 border-black px-4 py-3">
          <span className="text-sm font-black uppercase tracking-widest text-accent">Filtros</span>
          <button
            onClick={onClose}
            className="flex h-8 w-8 items-center justify-center border-2 border-black bg-bg-primary hover:bg-danger hover:text-black"
            aria-label="Cerrar filtros"
          >
            <X size={16} />
          </button>
        </div>

        <div className="flex flex-1 flex-col gap-5 overflow-y-auto p-4">
          {/* Scene filter */}
          <div className="flex flex-col gap-2">
            <span className="text-[0.625rem] font-black uppercase tracking-widest text-text-muted">Escena</span>
            <RetroSelect
              value={selectedScene}
              onChange={(event) => onSelectScene(event.target.value)}
              className="py-2 px-2 text-xs"
            >
              <option value="all">All scenes</option>
              {scenes.map((scene) => <option key={scene} value={scene}>{scene}</option>)}
            </RetroSelect>
          </div>

          {/* Platform filter */}
          <div className="flex flex-col gap-2">
            <span className="text-[0.625rem] font-black uppercase tracking-widest text-text-muted">
              Plataforma
              <span className="ml-2 text-text-muted/70">
                {visiblePlatforms.filter((p) => selectedPlatforms.has(p)).length}/{visiblePlatforms.length}
              </span>
            </span>
            <div className="flex flex-col gap-1">
              {visiblePlatforms.map((platform) => {
                const meta = PLATFORM_META[platform];
                const checked = selectedPlatforms.has(platform);
                return (
                  <label
                    key={platform}
                    className={`flex cursor-pointer items-center gap-2.5 border-2 border-black px-3 py-2.5 text-xs font-black uppercase transition-colors ${checked ? 'bg-bg-primary text-text-primary' : 'bg-bg-card text-text-muted'} hover:bg-accent/10`}
                  >
                    <input
                      type="checkbox"
                      checked={checked}
                      onChange={() => onTogglePlatform(platform)}
                      className="h-4 w-4 accent-accent"
                    />
                    <span className={`h-3 w-3 border border-black ${meta.color}`} />
                    {meta.icon}
                    <span>{meta.label}</span>
                  </label>
                );
              })}
            </div>
          </div>
        </div>

        {/* Reset to defaults (all scenes, every platform except server). */}
        <div className="border-t-2 border-black p-3">
          <button
            onClick={onReset}
            className="w-full border-2 border-black bg-bg-primary px-3 py-2 text-[0.625rem] font-black uppercase hover:bg-accent hover:text-black"
          >
            Reset filtros
          </button>
        </div>
      </div>
    </div>
  );
};
