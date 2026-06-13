import React, { useRef, useState } from 'react';
import { RetroBadge } from './retro';
import { formatFpsLabel } from '../lib/filters';

interface PlayerBottomSheetProps {
  open: boolean;
  onClose: () => void;
  players: any[];            // heartbeat objects
  geoByPlayer?: Record<string, { city?: string; country?: string; country_code?: string }>;
  history?: Record<string, { fps?: number[]; memory?: number[] }>;
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

const speed = (v: any): number => {
  if (!Array.isArray(v) || v.length < 3) return 0;
  return Math.sqrt(Number(v[0]) ** 2 + Number(v[1]) ** 2 + Number(v[2]) ** 2);
};

// Tiny dependency-free SVG sparkline. Auto-scales to its own min/max. Cheap:
// just a polyline, no chart lib, so it's fine to render one per visible player.
const Sparkline: React.FC<{ data: number[]; color: string; width?: number; height?: number }> = ({
  data, color, width = 56, height = 16,
}) => {
  const pts = (data || []).filter((n) => Number.isFinite(n));
  if (pts.length < 2) return <svg width={width} height={height} />;
  const min = Math.min(...pts);
  const max = Math.max(...pts);
  const span = max - min || 1;
  const step = width / (pts.length - 1);
  const d = pts.map((v, i) => `${(i * step).toFixed(1)},${(height - ((v - min) / span) * height).toFixed(1)}`).join(' ');
  return (
    <svg width={width} height={height} className="shrink-0">
      <polyline points={d} fill="none" stroke={color} strokeWidth={1.5} />
    </svg>
  );
};

const MetricCell: React.FC<{ label: string; value: string; spark?: number[]; color: string }> = ({
  label, value, spark, color,
}) => (
  <div className="flex flex-col gap-0.5 border-2 border-black bg-bg-card px-2 py-1">
    <div className="flex items-baseline justify-between gap-1">
      <span className="text-[0.5rem] font-black uppercase text-text-muted">{label}</span>
      <span className="text-[0.625rem] font-black" style={{ color }}>{value}</span>
    </div>
    {spark && <Sparkline data={spark} color={color} />}
  </div>
);

// Mobile modal that slides up from the bottom. Capped at 40vh with internal
// scroll, a drag handle, and drag-down-to-close. Compact rows: FPS, scene,
// time since last seen.
export const PlayerBottomSheet: React.FC<PlayerBottomSheetProps> = ({
  open, onClose, players, geoByPlayer, history, activeId, onSelect,
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
        className="relative bg-bg-card border-t-4 border-black rounded-t-2xl flex flex-col max-h-[65vh] animate-in slide-in-from-bottom duration-200"
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
            const mem = Number(p.memory_mb) || 0;
            const spd = speed(p.velocity);
            const stale = hb.timestamp ? (now - hb.timestamp * 1000) / 1000 : 0;
            const isActive = hb.player_id === activeId;
            const official = hb.intake_mode === 'admin' || hb.intake_mode === 'ingest';
            const location = formatLocation(geoByPlayer?.[hb.player_id]);
            const hist = history?.[hb.player_id];
            const fpsSpark = (hist?.fps || []).slice(-40);
            const memSpark = (hist?.memory || []).filter((m) => m > 0).slice(-40);
            // Prefer tag name, then location, and only fall back to the raw id
            // when we have neither a name nor a known location.
            const label = hb.display_name || location || hb.player_id;
            const showId = !hb.display_name && !location;
            return (
              <button
                key={hb.player_id}
                onClick={() => { onSelect(hb.player_id); onClose(); }}
                className={`text-left p-3 border-2 flex flex-col gap-2 transition-colors
                  ${isActive ? 'border-accent bg-accent/10' : 'border-black bg-bg-primary'}`}
              >
                <div className="flex items-start justify-between gap-3">
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
                    <div className="text-[0.625rem] text-text-muted flex flex-wrap gap-x-3 mt-0.5">
                      <span className="text-accent truncate max-w-[110px]">{p.scene || 'unknown'}</span>
                      <span className={official ? 'text-success' : 'text-warning'}>{official ? 'official' : 'canary'}</span>
                      {p.focused === false && (
                        <span className="text-text-muted/80 uppercase" title="Ventana en segundo plano — telemetría reducida">unfocused</span>
                      )}
                      <span>{stale.toFixed(1)}s ago</span>
                    </div>
                  </div>
                  <RetroBadge color={fpsColor(fps)}>{formatFpsLabel(fps)}</RetroBadge>
                </div>

                {/* Live metrics with mini sparklines. */}
                <div className="grid grid-cols-3 gap-1.5">
                  <MetricCell label="FPS" value={formatFpsLabel(fps).replace(' FPS', '')} spark={fpsSpark} color="#7fd1ff" />
                  <MetricCell label="RAM" value={`${mem.toFixed(0)} MB`} spark={memSpark.length ? memSpark : undefined} color="#3fb950" />
                  <MetricCell label="Vel" value={`${spd.toFixed(1)} m/s`} color="#d29922" />
                </div>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
};
