import React from 'react';
import { X, ChevronRight } from 'lucide-react';
import { PLATFORM_META } from './PlatformFilter';

const KNOWN_ORDER = ['server', 'android', 'linux', 'windows', 'macos', 'web'];

// Quick presets for the History min-duration filter (seconds). 13s aligns with
// WARMUP_SECONDS so "13s" drops sessions that are essentially only bootup.
const MIN_DURATION_PRESETS = [0, 13, 30, 60];

interface FiltersContentProps {
  platforms: string[];
  selectedPlatforms: Set<string>;
  onTogglePlatform: (platform: string) => void;
  scenes: string[];
  selectedScene: string;
  onSelectScene: (scene: string) => void;
  minDuration: number;
  onSetMinDuration: (seconds: number) => void;
  onReset: () => void;
}

// The actual filter controls, shared by the mobile overlay drawer and the
// desktop docked sidebar.
const FiltersContent: React.FC<FiltersContentProps> = ({
  platforms, selectedPlatforms, onTogglePlatform,
  scenes, selectedScene, onSelectScene,
  minDuration, onSetMinDuration, onReset,
}) => {
  const visiblePlatforms = KNOWN_ORDER.filter((p) => platforms.includes(p));
  const isCustomDuration = !MIN_DURATION_PRESETS.includes(minDuration);

  return (
    <>
      <div className="flex flex-1 flex-col gap-5 overflow-y-auto p-4">
        {/* Scene filter — explicit one-by-one selector instead of a dropdown. */}
        <div className="flex flex-col gap-2">
          <span className="text-[0.625rem] font-black uppercase tracking-widest text-text-muted">Escena</span>
          <div className="flex flex-col gap-1">
            <SceneOption
              label="Todas las escenas"
              active={selectedScene === 'all'}
              onClick={() => onSelectScene('all')}
            />
            {scenes.map((scene) => (
              <SceneOption
                key={scene}
                label={scene}
                active={selectedScene === scene}
                onClick={() => onSelectScene(scene)}
              />
            ))}
          </div>
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

        {/* History min-duration filter — excludes very short sessions (mostly
            bootup noise) from the History list and aggregate charts. */}
        <div className="flex flex-col gap-2">
          <span className="text-[0.625rem] font-black uppercase tracking-widest text-text-muted">
            Duración mínima (History)
          </span>
          <div className="flex flex-wrap gap-1">
            {MIN_DURATION_PRESETS.map((seconds) => {
              const active = minDuration === seconds;
              return (
                <button
                  key={seconds}
                  type="button"
                  onClick={() => onSetMinDuration(seconds)}
                  className={`border-2 border-black px-2.5 py-1.5 text-[0.625rem] font-black uppercase transition-colors ${active ? 'bg-accent text-black' : 'bg-bg-primary text-text-muted hover:bg-accent/10'}`}
                >
                  {seconds === 0 ? 'Todas' : `${seconds}s`}
                </button>
              );
            })}
          </div>
          <label className="flex items-center gap-2 text-[0.625rem] font-black uppercase text-text-muted">
            Custom
            <input
              type="number"
              min={0}
              value={isCustomDuration ? minDuration : ''}
              placeholder="s"
              onChange={(event) => {
                const next = Number(event.target.value);
                onSetMinDuration(Number.isFinite(next) && next > 0 ? next : 0);
              }}
              className="w-20 border-2 border-black bg-bg-primary px-2 py-1 text-xs font-black text-text-primary"
            />
            <span>s</span>
          </label>
        </div>
      </div>

      {/* Reset to defaults (all scenes, every platform except server, no min). */}
      <div className="border-t-2 border-black p-3">
        <button
          onClick={onReset}
          className="w-full border-2 border-black bg-bg-primary px-3 py-2 text-[0.625rem] font-black uppercase hover:bg-accent hover:text-black"
        >
          Reset filtros
        </button>
      </div>
    </>
  );
};

const SceneOption: React.FC<{ label: string; active: boolean; onClick: () => void }> = ({
  label, active, onClick,
}) => (
  <button
    type="button"
    onClick={onClick}
    className={`flex items-center justify-between gap-2 border-2 border-black px-3 py-2 text-left text-xs font-black uppercase transition-colors ${active ? 'bg-accent text-black' : 'bg-bg-card text-text-muted hover:bg-accent/10'}`}
  >
    <span className="truncate">{label}</span>
    {active && <ChevronRight size={14} className="shrink-0" />}
  </button>
);

interface FiltersDrawerProps extends FiltersContentProps {
  open: boolean;
  onClose: () => void;
}

// Mobile slide-in overlay (right). On desktop the same filters live in the
// docked FiltersSidebar instead — this overlay is hidden there (see App.tsx,
// which only opens it on smaller viewports).
export const FiltersDrawer: React.FC<FiltersDrawerProps> = ({ open, onClose, ...content }) => (
  <div
    className={`fixed inset-0 z-[9000] xl:hidden ${open ? '' : 'pointer-events-none'}`}
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
      <FiltersContent {...content} />
    </div>
  </div>
);

interface FiltersSidebarProps extends FiltersContentProps {
  collapsed: boolean;
  onToggleCollapsed: () => void;
}

// Desktop docked, collapsible sidebar. Rendered as a sibling column next to the
// main content (xl+ only). Collapsing shrinks it to a thin rail with a reopen
// affordance so the toggle stays reachable.
export const FiltersSidebar: React.FC<FiltersSidebarProps> = ({
  collapsed, onToggleCollapsed, ...content
}) => {
  if (collapsed) return null;

  return (
    <aside className="hidden h-full w-72 shrink-0 flex-col border-l-4 border-black bg-bg-card xl:flex">
      <div className="flex items-center justify-between border-b-4 border-black px-4 py-3">
        <span className="text-sm font-black uppercase tracking-widest text-accent">Filtros</span>
        <button
          onClick={onToggleCollapsed}
          className="flex h-8 w-8 items-center justify-center border-2 border-black bg-bg-primary hover:bg-accent hover:text-black"
          aria-label="Colapsar filtros"
          title="Colapsar filtros"
        >
          <ChevronRight size={16} />
        </button>
      </div>
      <FiltersContent {...content} />
    </aside>
  );
};
