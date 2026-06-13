import React, { useRef, useState } from 'react';
import { RetroBadge } from './retro';

interface PlayerBottomSheetProps {
  open: boolean;
  onClose: () => void;
  players: any[];            // heartbeat objects
  geoByPlayer?: Record<string, { city?: string; country?: string; country_code?: string }>;
  activeId?: string | null;
  onSelect: (playerId: string) => void;
}

// "City, Country" when known; gracefully drops missing halves.
const formatLocation = (geo?: { city?: string; country?: string }): string => {
  if (!geo) return '';
  const parts = [geo.city, geo.country].filter((s) => s && s !== 'unknown');
  return parts.join(', ');
};

const fpsColor = (f: number): 'success' | 'warning' | 'danger' =>
  f > 45 ? 'success' : f > 30 ? 'warning' : 'danger';

// Mobile modal that slides up from the bottom. Capped at 40vh with internal
// scroll, a drag handle, and drag-down-to-close. Compact rows: FPS, scene,
// time since last seen.
export const PlayerBottomSheet: React.FC<PlayerBottomSheetProps> = ({
  open, onClose, players, geoByPlayer, activeId, onSelect,
}) => {
  const [dragY, setDragY] = useState(0);
  const startY = useRef<number | null>(null);

  if (!open) return null;

  const onTouchStart = (e: React.TouchEvent) => { startY.current = e.touches[0].clientY; };
  const onTouchMove = (e: React.TouchEvent) => {
    if (startY.current == null) return;
    const dy = e.touches[0].clientY - startY.current;
    setDragY(Math.max(0, dy)); // only allow dragging down
  };
  const onTouchEnd = () => {
    if (dragY > 80) onClose();
    setDragY(0);
    startY.current = null;
  };

  const now = Date.now();

  return (
    <div className="fixed inset-0 z-[9000] flex flex-col justify-end" onClick={onClose}>
      <div className="absolute inset-0 bg-black/70" />
      <div
        className="relative bg-bg-card border-t-4 border-black rounded-t-2xl flex flex-col max-h-[40vh] animate-in slide-in-from-bottom duration-200"
        style={{ transform: `translateY(${dragY}px)` }}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Drag handle */}
        <div
          className="flex flex-col items-center pt-2 pb-1 cursor-grab active:cursor-grabbing touch-none"
          onTouchStart={onTouchStart}
          onTouchMove={onTouchMove}
          onTouchEnd={onTouchEnd}
        >
          <div className="w-10 h-1.5 rounded-full bg-text-muted/60" />
          <span className="mt-2 text-[0.625rem] uppercase font-black tracking-widest text-text-muted">
            {players.length} {players.length === 1 ? 'Player' : 'Players'}
          </span>
        </div>

        <div className="flex-1 overflow-y-auto px-3 pb-4 flex flex-col gap-2">
          {players.length === 0 && (
            <div className="text-center text-text-muted italic text-xs py-6">No active players</div>
          )}
          {players.map((hb) => {
            const p = hb.player || {};
            const fps = Math.round(p.fps || 0);
            const stale = hb.timestamp ? (now - hb.timestamp * 1000) / 1000 : 0;
            const isActive = hb.player_id === activeId;
            const official = hb.intake_mode === 'admin' || hb.intake_mode === 'ingest';
            const location = formatLocation(geoByPlayer?.[hb.player_id]);
            // Prefer tag name, then location, and only fall back to the raw id
            // when we have neither a name nor a known location.
            const label = hb.display_name || location || hb.player_id;
            const showId = !hb.display_name && !location;
            return (
              <button
                key={hb.player_id}
                onClick={() => { onSelect(hb.player_id); onClose(); }}
                className={`text-left p-3 border-2 flex items-center justify-between gap-3 transition-colors
                  ${isActive ? 'border-accent bg-accent/10' : 'border-black bg-bg-primary'}`}
              >
                <div className="min-w-0">
                  <div className="text-xs font-bold truncate flex items-center gap-1.5">
                    {hb.color && (
                      <span className="inline-block w-2 h-2 rounded-full shrink-0" style={{ backgroundColor: hb.color }} />
                    )}
                    <span className="truncate">{label}</span>
                  </div>
                  {hb.display_name && location && (
                    <div className="text-[0.5625rem] text-text-muted truncate">{location}</div>
                  )}
                  {showId && (
                    <div className="text-[0.5625rem] text-text-muted truncate font-mono">{hb.player_id}</div>
                  )}
                  <div className="text-[0.625rem] text-text-muted flex gap-3 mt-0.5">
                    <span className="text-accent truncate max-w-[110px]">{p.scene || 'unknown'}</span>
                    <span className={official ? 'text-success' : 'text-warning'}>{official ? 'official' : 'canary'}</span>
                    {p.focused === false && (
                      <span className="text-text-muted/80 uppercase" title="Ventana en segundo plano — telemetría reducida">unfocused</span>
                    )}
                    <span>{stale.toFixed(1)}s ago</span>
                  </div>
                </div>
                <RetroBadge color={fpsColor(fps)}>{fps} FPS</RetroBadge>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
};
