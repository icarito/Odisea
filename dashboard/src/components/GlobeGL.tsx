import React, { useRef, useEffect, useMemo, useCallback, useState } from 'react';
import Globe from 'react-globe.gl';
import { feature } from 'topojson-client';
import type { Topology, GeometryCollection } from 'topojson-specification';
import type { GeoPlayer } from '../types';

interface GroupedPlayer {
  latitude: number;
  longitude: number;
  country: string;
  city: string;
  count: number;
  status: 'connected' | 'recent' | 'old';
  player_id?: string;
}

interface GlobeGLProps {
  players: GeoPlayer[];
}

const POINT_COLORS: Record<string, string> = {
  connected: '#3fb950',
  recent: '#d29922',
  old: '#8b949e',
};

export const GlobeGL: React.FC<GlobeGLProps> = ({ players }) => {
  const globeRef = useRef<any>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const [countries, setCountries] = useState<object[]>([]);
  const [selected, setSelected] = useState<GroupedPlayer | null>(null);
  const [dimensions, setDimensions] = useState({ width: 0, height: 0 });

  useEffect(() => {
    fetch('https://cdn.jsdelivr.net/npm/world-atlas@2/countries-110m.json')
      .then(r => r.json())
      .then((topo: Topology) => {
        const geo = feature(topo, topo.objects.countries as GeometryCollection);
        setCountries((geo as any).features);
      })
      .catch(console.error);
  }, []);

  // Measure container for explicit dimensions (avoids 0-height issues in flex layouts)
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const ro = new ResizeObserver(entries => {
      const { width, height } = entries[0].contentRect;
      setDimensions({ width, height });
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  // Configure controls after globe mounts
  useEffect(() => {
    const globe = globeRef.current;
    if (!globe || dimensions.width === 0) return;
    const controls = globe.controls();
    controls.autoRotate = true;
    controls.autoRotateSpeed = 0.5;
    controls.enablePan = false;
    controls.minDistance = 150;
    controls.maxDistance = 600;
    controls.enableDamping = true;
    controls.dampingFactor = 0.12;

    const stop = () => { controls.autoRotate = false; };
    const resume = () => { setTimeout(() => { controls.autoRotate = true; }, 5000); };
    controls.addEventListener('start', stop);
    controls.addEventListener('end', resume);
    return () => {
      controls.removeEventListener('start', stop);
      controls.removeEventListener('end', resume);
    };
  }, [dimensions.width]);

  const pointData = useMemo<GroupedPlayer[]>(() => {
    const groups: Record<string, GroupedPlayer> = {};
    players.forEach(p => {
      const key = `${p.latitude.toFixed(2)}|${p.longitude.toFixed(2)}`;
      if (!groups[key]) {
        groups[key] = {
          latitude: p.latitude,
          longitude: p.longitude,
          country: p.country,
          city: p.city,
          count: 0,
          status: 'old',
          player_id: p.player_id,
        };
      }
      groups[key].count++;
      if (p.status === 'connected') groups[key].status = 'connected';
      else if (p.status === 'recent' && groups[key].status === 'old') groups[key].status = 'recent';
    });
    return Object.values(groups);
  }, [players]);

  const pointColor = useCallback((p: object) => POINT_COLORS[(p as GroupedPlayer).status], []);
  const pointRadius = useCallback((p: object) => Math.sqrt((p as GroupedPlayer).count) * 0.25 + 0.3, []);

  const handlePointClick = useCallback((point: object) => {
    const p = point as GroupedPlayer;
    const key = `${p.latitude.toFixed(2)}|${p.longitude.toFixed(2)}`;
    const selKey = selected
      ? `${selected.latitude.toFixed(2)}|${selected.longitude.toFixed(2)}`
      : null;
    if (selKey === key) {
      if (p.player_id) window.location.search = `?player=${p.player_id}`;
    } else {
      setSelected(p);
    }
  }, [selected]);

  return (
    <div ref={containerRef} className="h-full w-full relative" style={{ background: '#080a0f' }}>
      {dimensions.width > 0 && (
        <Globe
          ref={globeRef}
          width={dimensions.width}
          height={dimensions.height}
          backgroundColor="rgba(8,10,15,1)"
          atmosphereColor="#7fd1ff"
          atmosphereAltitude={0.15}
          polygonsData={countries}
          polygonCapColor={() => '#0a1628'}
          polygonSideColor={() => 'transparent'}
          polygonStrokeColor={() => '#1e4f8f'}
          polygonAltitude={0.001}
          pointsData={pointData}
          pointLat={(p: object) => (p as GroupedPlayer).latitude}
          pointLng={(p: object) => (p as GroupedPlayer).longitude}
          pointColor={pointColor}
          pointRadius={pointRadius}
          pointAltitude={0.01}
          pointsMerge={false}
          onPointClick={handlePointClick}
          onGlobeClick={() => setSelected(null)}
        />
      )}

      {selected && (
        <div className="absolute bottom-4 left-4 right-4 bg-[#0d1117]/95 border border-accent rounded-lg p-3 flex items-center justify-between gap-3 shadow-lg">
          <div className="min-w-0">
            <div className="font-bold text-sm truncate">{selected.city}, {selected.country}</div>
            <div className="text-[0.625rem] text-text-muted mt-0.5">
              {selected.count} jugador{selected.count !== 1 ? 'es' : ''} · toca de nuevo para ver
            </div>
          </div>
          <div className="flex items-center gap-2 shrink-0">
            {selected.player_id && (
              <button
                onClick={() => { window.location.search = `?player=${selected.player_id}`; }}
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
