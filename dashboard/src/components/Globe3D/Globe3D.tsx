import React, { useEffect, useMemo, useRef, useState } from 'react';
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
}

const STATUS_COLOR: Record<GeoPlayer['status'], string> = {
  connected: '#3fb950',
  recent: '#d29922',
  old: '#8b949e',
};

const STATUS_RANK: Record<GeoPlayer['status'], number> = {
  connected: 2,
  recent: 1,
  old: 0,
};

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
      };
    }
    const g = groups[key];
    g.count++;
    if (p.display_name) g.names.push(p.display_name);
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

  const isMobile = size.width > 0 && size.width < 768;

  const points = useMemo(() => groupPlayers(players), [players]);

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
    controls.autoRotate = true;
    controls.autoRotateSpeed = 0.4;
    controls.enablePan = false;
    controls.minDistance = 180;
    controls.maxDistance = 600;
    const stop = () => {
      controls.autoRotate = false;
    };
    controls.addEventListener('start', stop);
    return () => controls.removeEventListener('start', stop);
  }, [size.width]);

  const handlePointClick = (obj: object) => {
    const p = obj as GroupedPlayer;
    if (isMobile) {
      if (selected?.key === p.key) {
        if (p.player_id) onSelectPlayer?.(p.player_id);
      } else {
        setSelected(p);
        globeRef.current?.pointOfView(
          { lat: p.latitude, lng: p.longitude, altitude: 1.5 },
          800,
        );
      }
    } else if (p.player_id) {
      onSelectPlayer?.(p.player_id);
    }
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
          pointColor={(d) => STATUS_COLOR[(d as GroupedPlayer).status]}
          pointAltitude={(d) => 0.01 + Math.min((d as GroupedPlayer).count * 0.01, 0.12)}
          pointRadius={(d) =>
            (isMobile ? 0.45 : 0.28) + Math.min((d as GroupedPlayer).count * 0.05, 0.5)
          }
          pointsMerge={false}
          pointLabel={(d) => {
            const p = d as GroupedPlayer;
            return `<div style="background:rgba(0,0,0,.8);border:1px solid #3fb950;padding:6px 8px;border-radius:4px;font-size:11px;white-space:nowrap"><b>${p.city}, ${p.country}</b><br/>${p.count} jugador${p.count !== 1 ? 'es' : ''}</div>`;
          }}
          onPointClick={handlePointClick}
        />
      )}

      {/* Mobile info overlay — first tap selects, second navigates */}
      {selected && (
        <div className="absolute bottom-4 left-4 right-4 bg-[#0d1117]/95 border border-accent rounded-lg p-3 flex items-center justify-between gap-3 shadow-lg">
          <div className="min-w-0">
            <div className="font-bold text-sm truncate">
              {selected.city}, {selected.country}
            </div>
            <div className="text-[0.625rem] text-text-muted mt-0.5">
              {selected.count} jugador{selected.count !== 1 ? 'es' : ''} · toca de nuevo para ver
            </div>
          </div>
          <div className="flex items-center gap-2 shrink-0">
            {selected.player_id && (
              <button
                onClick={() => {
                  onSelectPlayer?.(selected.player_id);
                }}
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
