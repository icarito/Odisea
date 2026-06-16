import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Maximize, Minimize } from 'lucide-react';
import Globe, { type GlobeMethods } from 'react-globe.gl';
import { feature } from 'topojson-client';
import type { Topology, GeometryCollection } from 'topojson-specification';
import type { GeoPlayer } from '../../types';

interface Globe3DProps {
  players: GeoPlayer[];
  onSelectPlayer?: (playerId: string) => void;
}

interface GroupedPlayer {
  key: string;
  latitude: number;
  longitude: number;
  city: string;
  country: string;
  count: number;
  status: GeoPlayer['status'];
  player_id: string;
  names: string[];
  color?: string;
  historical: boolean;
  hits: number;
  player_count: number;
}

const STATUS_COLOR: Record<GeoPlayer['status'], string> = {
  connected: '#3fb950',
  recent: '#d29922',
  old: '#8b949e',
};

const STATUS_LABEL: Record<GeoPlayer['status'], string> = {
  connected: 'en línea',
  recent: 'reciente',
  old: 'inactivo',
};

const STATUS_RANK: Record<GeoPlayer['status'], number> = {
  connected: 2,
  recent: 1,
  old: 0,
};

// ISO 3166-1 alpha-2 code -> flag emoji (regional indicator pair). Empty for
// missing/invalid codes so the UI just shows the name.
const countryFlag = (code?: string): string => {
  const c = String(code || '').trim().toUpperCase();
  if (!/^[A-Z]{2}$/.test(c)) return '';
  return String.fromCodePoint(...[...c].map((ch) => 0x1f1e6 + ch.charCodeAt(0) - 65));
};

const escapeHtml = (value: string) => (
  value.replace(/[&<>"']/g, (char) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  }[char] || char))
);

function groupPlayers(players: GeoPlayer[]): GroupedPlayer[] {
  const groups: Record<string, GroupedPlayer> = {};
  for (const p of players) {
    const key = `${p.latitude.toFixed(2)}|${p.longitude.toFixed(2)}`;
    if (!groups[key]) {
      groups[key] = {
        key,
        latitude: p.latitude,
        longitude: p.longitude,
        city: p.city,
        country: p.country,
        count: 0,
        status: 'old',
        player_id: p.player_id,
        names: [],
        color: p.color,
        historical: Boolean(p.historical),
        hits: 0,
        player_count: 0,
      };
    }
    const g = groups[key];
    g.count++;
    if (p.display_name && !g.names.includes(p.display_name)) g.names.push(p.display_name);
    if (!g.color && p.color) g.color = p.color;
    g.historical = g.historical || Boolean(p.historical);
    g.hits += Number(p.hits || 0);
    g.player_count += Number(p.player_count || 0);
    if (STATUS_RANK[p.status] > STATUS_RANK[g.status]) g.status = p.status;
  }
  return Object.values(groups);
}

export const Globe3D: React.FC<Globe3DProps> = ({ players, onSelectPlayer }) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const globeRef = useRef<GlobeMethods | undefined>(undefined);
  const [size, setSize] = useState({ width: 0, height: 0 });
  const [countries, setCountries] = useState<object[]>([]);
  const [selected, setSelected] = useState<GroupedPlayer | null>(null);
  const [hovered, setHovered] = useState<GroupedPlayer | null>(null);
  const [camDistance, setCamDistance] = useState(600);
  // When on, the camera re-centers on the latest activity as it moves around.
  // On by default so a new player is framed automatically.
  const [followActivity, setFollowActivity] = useState(true);
  const [showTopCountries, setShowTopCountries] = useState(true);
  const [isFullscreen, setIsFullscreen] = useState(false);

  // Native fullscreen on the bordered box (the container's parent). The existing
  // ResizeObserver measures that same box, so the globe resizes to fill the
  // screen automatically when we enter/exit.
  const toggleFullscreen = () => {
    const box = containerRef.current?.parentElement;
    if (!box) return;
    if (document.fullscreenElement) {
      document.exitFullscreen().catch(() => {});
    } else {
      box.requestFullscreen().catch(() => {});
    }
  };
  useEffect(() => {
    const onChange = () => setIsFullscreen(Boolean(document.fullscreenElement));
    document.addEventListener('fullscreenchange', onChange);
    return () => document.removeEventListener('fullscreenchange', onChange);
  }, []);

  const isMobile = size.width > 0 && size.width < 768;

  const points = useMemo(() => groupPlayers(players), [players]);

  // Top countries by player presence, aggregated across all geo points. Counts
  // distinct points (locations) and players per country.
  const topCountries = useMemo(() => {
    const byCountry = new Map<string, { code: string; country: string; count: number }>();
    for (const p of players) {
      const code = String(p.country_code || '').toUpperCase();
      const country = String(p.country || '').trim();
      if ((!code && !country) || country.toLowerCase() === 'unknown') continue;
      const key = code || country;
      const cur = byCountry.get(key) || { code, country: country || code, count: 0 };
      cur.count += Number(p.player_count || 1) || 1;
      byCountry.set(key, cur);
    }
    return [...byCountry.values()].sort((a, b) => b.count - a.count).slice(0, 8);
  }, [players]);

  // Most "recent" group: prefer live (connected) over recent over old; break
  // ties by how many players sit there. Used to center the camera on landing.
  const latestGroup = useMemo(() => {
    let best: GroupedPlayer | null = null;
    for (const g of points) {
      if (!best
        || STATUS_RANK[g.status] > STATUS_RANK[best.status]
        || (STATUS_RANK[g.status] === STATUS_RANK[best.status] && g.count > best.count)) {
        best = g;
      }
    }
    return best;
  }, [points]);

  // Center the globe on the latest players the first time we have both a globe
  // instance and at least one point. Runs once per "had no center yet" → keeps
  // auto-rotation afterwards and never fights the user's manual navigation.
  const centeredRef = useRef(false);
  // Last lat/lng we animated the camera to. `latestGroup` is rebuilt (new object
  // identity) on every players poll even when the actual hottest location hasn't
  // moved, so without this guard the effect would re-fire each poll and restart
  // a 1s camera tween mid-flight — the visible follow "flicker"/glitch. We only
  // re-center when the followed coordinates genuinely change.
  const lastCenterRef = useRef<{ lat: number; lng: number } | null>(null);
  useEffect(() => {
    const g = globeRef.current;
    if (!g || !latestGroup) return;
    // Center once on first load, and keep re-centering while "follow" is on.
    if (centeredRef.current && !followActivity) return;
    const firstCenter = !centeredRef.current;
    // Skip if the followed location hasn't actually moved — avoids restarting
    // the camera tween (and the flicker) on every unchanged poll.
    const last = lastCenterRef.current;
    const moved = !last
      || Math.abs(last.lat - latestGroup.latitude) > 1e-4
      || Math.abs(last.lng - latestGroup.longitude) > 1e-4;
    if (!firstCenter && !moved) return;
    centeredRef.current = true;
    lastCenterRef.current = { lat: latestGroup.latitude, lng: latestGroup.longitude };
    // First center frames the activity at a fixed altitude; subsequent follow
    // re-centers preserve whatever zoom the user has dialed in (only lat/lng move),
    // so the user stays in control of zoom even while following.
    const current = g.pointOfView();
    const altitude = firstCenter ? (followActivity ? 0.9 : 2.2) : (current?.altitude ?? 0.9);
    g.pointOfView(
      { lat: latestGroup.latitude, lng: latestGroup.longitude, altitude },
      1000,
    );
  }, [latestGroup, size.width, followActivity]);

  // Following disables auto-rotation so the camera holds on the activity.
  useEffect(() => {
    const g = globeRef.current;
    if (!g) return;
    const controls = g.controls();
    if (followActivity) controls.autoRotate = false;
  }, [followActivity]);

  // Responsive sizing. The container is absolute inset-0, so the parent's box is
  // the source of truth; measure that. First measure is deferred to the next
  // frame so layout has settled, and any 0×0 reads are simply ignored until a
  // real size arrives via the ResizeObserver.
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const target = el.parentElement ?? el;
    const measure = () => {
      const box = target.getBoundingClientRect();
      const w = Math.round(box.width);
      const h = Math.round(box.height);
      setSize((prev) => (w > 0 && h > 0 && (w !== prev.width || h !== prev.height) ? { width: w, height: h } : prev));
    };
    const ro = new ResizeObserver(measure);
    ro.observe(target);
    const raf = requestAnimationFrame(measure);
    return () => {
      ro.disconnect();
      cancelAnimationFrame(raf);
    };
  }, []);

  // Country polygons for borders.
  useEffect(() => {
    let cancelled = false;
    fetch('https://cdn.jsdelivr.net/npm/world-atlas@2/countries-110m.json')
      .then((r) => r.json())
      .then((topo: Topology) => {
        if (cancelled) return;
        const fc = feature(topo, topo.objects.countries as GeometryCollection);
        setCountries(fc.features as object[]);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, []);

  // Gentle auto-rotation until the user interacts.
  useEffect(() => {
    const g = globeRef.current;
    if (!g) return;
    const controls = g.controls();
    // Don't auto-rotate while following — the camera should hold on the activity.
    controls.autoRotate = !followActivity;
    controls.autoRotateSpeed = 0.4;
    controls.enablePan = false;
    // Allow zooming in much closer (street-ish) while keeping a sane far bound.
    controls.minDistance = 110;
    controls.maxDistance = 600;
    // Track camera distance so markers can shrink and reveal more detail when
    // the user zooms in. react-globe.gl's camera lives on the same controls.
    const onChange = () => {
      const cam: any = (controls as any).object;
      if (cam?.position) setCamDistance(cam.position.length());
    };
    controls.addEventListener('change', onChange);
    onChange();
    // 'start' fires on a rotate/pan drag (pointer down), but NOT on wheel/pinch
    // zoom — so dragging the globe drops follow and stops auto-rotation, while
    // zooming keeps follow active.
    const stop = () => {
      controls.autoRotate = false;
      setFollowActivity(false);
    };
    controls.addEventListener('start', stop);
    return () => {
      controls.removeEventListener('start', stop);
      controls.removeEventListener('change', onChange);
    };
  }, [size.width]);

  // 0 (far) → 1 (close): drives marker shrink + extra label detail when zoomed in.
  const zoomFactor = useMemo(() => {
    const t = (600 - camDistance) / (600 - 110);
    return Math.max(0, Math.min(1, t));
  }, [camDistance]);
  const isClose = zoomFactor > 0.55;

  const handlePointClick = (obj: object) => {
    const p = obj as GroupedPlayer;
    // Clicking a point shows the info overlay and frames it; clicking again (or
    // the overlay's "Ver" button) drills into the player. Same flow on desktop
    // and mobile. Clicking a point drops follow so the camera stays put.
    if (selected?.key === p.key) {
      if (p.player_id) onSelectPlayer?.(p.player_id);
      return;
    }
    setFollowActivity(false);
    setSelected(p);
    globeRef.current?.pointOfView(
      { lat: p.latitude, lng: p.longitude, altitude: 1.2 },
      800,
    );
  };

  return (
    <div ref={containerRef} className="absolute inset-0 h-full w-full bg-[#080a0f]">
      {size.width > 0 && size.height > 0 && (
        <Globe
          ref={globeRef}
          width={size.width}
          height={size.height}
          backgroundColor="#080a0f"
          globeImageUrl="//cdn.jsdelivr.net/npm/three-globe/example/img/earth-night.jpg"
          showAtmosphere
          atmosphereColor="#3a7bd5"
          atmosphereAltitude={0.18}
          // Country borders
          polygonsData={countries}
          polygonCapColor={() => 'rgba(0,0,0,0)'}
          polygonSideColor={() => 'rgba(0,0,0,0)'}
          polygonStrokeColor={() => '#1e4f8f'}
          polygonAltitude={0.005}
          // Player dots
          pointsData={points}
          pointLat="latitude"
          pointLng="longitude"
          pointColor={(d) => (d as GroupedPlayer).color || STATUS_COLOR[(d as GroupedPlayer).status]}
          pointAltitude={(d) => 0.01 + Math.min((d as GroupedPlayer).count * 0.01, 0.12)}
          pointRadius={(d) => {
            // Shrink markers hard as the camera gets closer so dense clusters
            // separate and stay distinguishable at street-level zoom (down to
            // ~15% of the far-view size).
            const shrink = 1 - zoomFactor * 0.85;
            const base = (isMobile ? 0.42 : 0.26) + Math.min((d as GroupedPlayer).count * 0.04, 0.4) * (1 - zoomFactor * 0.7);
            return base * shrink;
          }}
          pointsMerge={false}
          pointLabel={(d) => {
            const p = d as GroupedPlayer;
            const historical = p.historical ? `<br/><span style="color:#8b949e">${p.hits} hits historicos</span>` : '';
            // When zoomed in, surface more names and the player count breakdown.
            const nameLimit = isClose ? 8 : 3;
            const names = p.names.length ? `<br/><span style="color:#7fd1ff">${escapeHtml(p.names.slice(0, nameLimit).join(', '))}${p.names.length > nameLimit ? ` +${p.names.length - nameLimit}` : ''}</span>` : '';
            const detail = isClose
              ? `<br/><span style="color:#8b949e">${p.player_count || p.count} jugador${(p.player_count || p.count) !== 1 ? 'es' : ''} · ${STATUS_LABEL[p.status]}</span>`
              : '';
            return `<div style="background:rgba(0,0,0,.8);border:1px solid #3fb950;padding:6px 8px;border-radius:4px;font-size:11px;white-space:nowrap"><b>${escapeHtml(p.city)}, ${escapeHtml(p.country)}</b><br/>${p.count} punto${p.count !== 1 ? 's' : ''}${names}${detail}${historical}</div>`;
          }}
          onPointClick={handlePointClick}
          onPointHover={(d) => setHovered((d as GroupedPlayer) || null)}
        />
      )}

      {/* Hover overlay (desktop): a compact card for the point under the cursor,
          shown only when nothing is click-selected. Touch devices use click. */}
      {hovered && !selected && (
        <div className="pointer-events-none absolute top-3 left-3 z-20 w-56 max-w-[70vw] border-2 border-black bg-[#0d1117]/95 p-2.5 shadow-[2px_2px_0px_0px_black]">
          <div className="flex items-center gap-2 min-w-0">
            <span className="w-2 h-2 rounded-full shrink-0" style={{ backgroundColor: hovered.color || STATUS_COLOR[hovered.status] }} />
            <span className="font-bold text-xs truncate">{hovered.city}, {hovered.country}</span>
          </div>
          {hovered.names.length > 0 && (
            <div className="text-[0.5625rem] text-accent truncate mt-0.5">
              {hovered.names.slice(0, 4).join(', ')}{hovered.names.length > 4 ? ` +${hovered.names.length - 4}` : ''}
            </div>
          )}
          <div className="text-[0.5625rem] text-text-muted mt-0.5">
            {(hovered.player_count || hovered.count)} jugador{(hovered.player_count || hovered.count) !== 1 ? 'es' : ''} · {STATUS_LABEL[hovered.status]}
            {hovered.historical ? ` · ${hovered.hits} hits` : ''}
          </div>
        </div>
      )}

      {/* Top-right controls: follow-activity toggle + fullscreen. */}
      <div className="absolute top-3 right-3 z-10 flex items-center gap-2">
        <button
          type="button"
          onClick={() => setFollowActivity((v) => !v)}
          className={`border-2 px-2.5 py-1 text-[0.625rem] font-black uppercase tracking-wide shadow-[2px_2px_0px_0px_black] transition-colors ${
            followActivity
              ? 'border-accent bg-accent text-black'
              : 'border-black bg-bg-card/90 text-text-muted hover:text-text-primary'
          }`}
          title="Centrar la cámara en la actividad más reciente"
        >
          Follow
        </button>
        <button
          type="button"
          onClick={toggleFullscreen}
          className="border-2 border-black bg-bg-card/90 p-1.5 text-text-muted shadow-[2px_2px_0px_0px_black] transition-colors hover:text-text-primary"
          title={isFullscreen ? 'Salir de pantalla completa' : 'Pantalla completa'}
          aria-label={isFullscreen ? 'Salir de pantalla completa' : 'Pantalla completa'}
        >
          {isFullscreen ? <Minimize size={14} /> : <Maximize size={14} />}
        </button>
      </div>

      {/* Top-countries toggle + panel, bottom-left. */}
      <button
        type="button"
        onClick={() => setShowTopCountries((v) => !v)}
        className={`absolute bottom-3 left-3 z-20 border-2 px-2.5 py-1 text-[0.625rem] font-black uppercase tracking-wide shadow-[2px_2px_0px_0px_black] transition-colors ${
          showTopCountries
            ? 'border-accent bg-accent text-black'
            : 'border-black bg-bg-card/90 text-text-muted hover:text-text-primary'
        }`}
        title="Top de países"
      >
        Top países
      </button>

      {showTopCountries && (
        <div className="absolute bottom-12 left-3 z-20 w-52 max-w-[70vw] border-2 border-black bg-[#0d1117]/95 shadow-[2px_2px_0px_0px_black]">
          <div className="border-b-2 border-black px-3 py-1.5 text-[0.625rem] font-black uppercase tracking-widest text-text-muted">
            Top países
          </div>
          {topCountries.length === 0 ? (
            <div className="px-3 py-3 text-center text-[0.625rem] text-text-muted">Sin datos de geo.</div>
          ) : (
            <ul className="max-h-56 overflow-y-auto">
              {topCountries.map((c, i) => (
                <li key={c.code || c.country} className="flex items-center justify-between gap-2 border-b border-black/40 px-3 py-1.5 last:border-b-0">
                  <span className="flex min-w-0 items-center gap-2 text-xs">
                    <span className="w-4 text-right text-[0.625rem] font-black text-text-muted">{i + 1}</span>
                    <span className="shrink-0">{countryFlag(c.code)}</span>
                    <span className="truncate font-bold">{c.country}</span>
                  </span>
                  <span className="shrink-0 text-[0.625rem] font-black text-accent">{c.count}</span>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}

      {/* Info overlay shown when a point is clicked (desktop + mobile). */}
      {selected && (
        <div className="absolute bottom-4 left-4 right-4 z-20 mx-auto max-w-md bg-[#0d1117]/95 border border-accent rounded-lg p-3 flex items-center justify-between gap-3 shadow-lg">
          <div className="min-w-0">
            <div className="flex items-center gap-2 min-w-0">
              <span className="w-2 h-2 rounded-full shrink-0" style={{ backgroundColor: selected.color || STATUS_COLOR[selected.status] }} />
              <span className="font-bold text-sm truncate">{selected.city}, {selected.country}</span>
            </div>
            {selected.names.length > 0 && (
              <div className="text-[0.625rem] text-accent truncate mt-0.5">
                {selected.names.slice(0, 4).join(', ')}{selected.names.length > 4 ? ` +${selected.names.length - 4}` : ''}
              </div>
            )}
            <div className="text-[0.625rem] text-text-muted mt-0.5">
              {(selected.player_count || selected.count)} jugador{(selected.player_count || selected.count) !== 1 ? 'es' : ''} · {STATUS_LABEL[selected.status]}
              {selected.historical ? ` · ${selected.hits} hits` : ''}
            </div>
          </div>
          <div className="flex items-center gap-2 shrink-0">
            {selected.player_id && !selected.historical && (
              <button
                onClick={() => onSelectPlayer?.(selected.player_id)}
                className="text-xs bg-accent/20 border border-accent/40 text-accent px-3 py-1.5 rounded font-bold"
              >
                Ver
              </button>
            )}
            <button
              onClick={() => setSelected(null)}
              className="text-text-muted text-lg leading-none px-1"
              aria-label="Cerrar"
            >
              ×
            </button>
          </div>
        </div>
      )}
    </div>
  );
};
