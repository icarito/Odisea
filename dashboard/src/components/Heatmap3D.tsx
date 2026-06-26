import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Canvas } from '@react-three/fiber';
import { OrbitControls, Grid, PerspectiveCamera, Html } from '@react-three/drei';
import * as THREE from 'three';

import { ChevronDown, ChevronUp, Maximize2, Minimize2, Download, Play, X } from 'lucide-react';
import { useSceneGeometryStream } from '../hooks/useSceneGeometry';

interface HeatmapCell {
  grid_x: number;
  grid_z: number;
  count: number;
  low_fps_count: number;
  avg_fps: number;
  min_fps: number;
  avg_mem: number;
}

export interface HotzoneMarker {
  id: string;
  grid_x?: number | null;
  grid_z?: number | null;
  scene?: string | null;
  trigger_type?: string | null;
  display_name?: string | null;
  player_id?: string | null;
  timestamp?: number | null;
  frame_count?: number | null;
  capture_duration?: number | null;
  file_size?: number | null;
  size_kb?: number | null;
}

// Punto 3D de jugador (ghost): posición real en la escena + FPS, para la nube
// 3D coloreada por rendimiento. Opcional — el dashboard clásico no la pasa.
export interface GhostPoint {
  x: number;
  y: number;
  z: number;
  fps: number;
}

interface Heatmap3DProps {
  data: HeatmapCell[];
  resolution: number;
  scene?: string;
  hotzones?: HotzoneMarker[];
  ghosts?: GhostPoint[];
  onSelectHotzone?: (hz: HotzoneMarker) => void;
  onDownloadHotzone?: (hz: HotzoneMarker) => void;
}

function lowFpsPct(cell: HeatmapCell): number {
  return cell.count ? (cell.low_fps_count / cell.count) * 100 : 0;
}

function cellColor(pct: number): string {
  if (pct >= 50) return '#ef4444';
  if (pct >= 30) return '#f97316';
  if (pct >= 10) return '#eab308';
  return '#22c55e';
}

// Extruded heat cell: height encodes severity so hotspots read as towers without
// needing the (previously tiny) floating tooltip. Hover/selection is lifted to the
// parent so the readable stats live in a fixed on-screen panel.
const Cell: React.FC<{
  cell: HeatmapCell;
  resolution: number;
  maxCount: number;
  selected: boolean;
  onHover: (cell: HeatmapCell | null) => void;
  onSelect: (cell: HeatmapCell) => void;
}> = ({ cell, resolution, maxCount, selected, onHover, onSelect }) => {
  const pct = lowFpsPct(cell);
  const color = cellColor(pct);
  // Height: blend low-fps severity with relative traffic so a busy-but-healthy
  // cell still reads as a presence, and a critical cell towers over it.
  const traffic = maxCount > 0 ? cell.count / maxCount : 0;
  // Scale tower height with cell size so the relief reads at any scene scale
  // (resolution grows for large scenes like OdiseaExterior).
  const height = resolution * (0.1 + (pct / 100) * 1.2 + traffic * 0.4);

  return (
    <group position={[cell.grid_x + resolution / 2, height / 2, cell.grid_z + resolution / 2]}>
      <mesh
        onPointerOver={(e) => { e.stopPropagation(); onHover(cell); }}
        onPointerOut={() => onHover(null)}
        onClick={(e) => { e.stopPropagation(); onSelect(cell); }}
      >
        <boxGeometry args={[resolution * 0.9, height, resolution * 0.9]} />
        <meshStandardMaterial
          color={color}
          transparent
          opacity={selected ? 0.95 : 0.6}
          emissive={color}
          emissiveIntensity={selected ? 0.5 : 0.15}
        />
      </mesh>
    </group>
  );
};

function makePointTexture(): THREE.Texture | null {
  const canvas = document.createElement('canvas');
  canvas.width = 32;
  canvas.height = 32;
  const ctx = canvas.getContext('2d');
  if (!ctx) return null;
  const g = ctx.createRadialGradient(16, 16, 0, 16, 16, 16);
  g.addColorStop(0, 'rgba(255,255,255,1)');
  g.addColorStop(0.55, 'rgba(255,255,255,0.7)');
  g.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 32, 32);
  const t = new THREE.CanvasTexture(canvas);
  t.needsUpdate = true;
  return t;
}

// Scene scatter cloud: the same point data the live viewport uses, drawn faded
// underneath the heat cells so the heatmap reads against real scene volume
// instead of an empty grid. Banded by HEIGHT (Y) so floors/walls/ceilings read
// as layers from a bird's-eye view, and sized in *screen pixels*
// (sizeAttenuation={false}) so the cloud is visible at any scene scale — Dome_Crio
// spans ~70u while OdiseaExterior spans ~2000u, and a world-unit point size that
// works for one is invisible for the other.
const SceneScatter: React.FC<{ points: [number, number, number][] }> = ({ points }) => {
  const texture = useMemo(makePointTexture, []);

  const bands = useMemo(() => {
    if (!points || points.length === 0) return [];
    let minY = Infinity, maxY = -Infinity;
    for (const p of points) {
      if (p[1] < minY) minY = p[1];
      if (p[1] > maxY) maxY = p[1];
    }
    const span = Math.max(1, maxY - minY);
    const low = minY + span * 0.33, high = minY + span * 0.66;
    // 0 = floor/low, 1 = mid, 2 = high/ceiling
    const buckets: [number, number, number][][] = [[], [], []];
    for (const p of points) {
      buckets[p[1] <= low ? 0 : p[1] <= high ? 1 : 2].push(p);
    }
    return buckets.map((pts) => {
      if (pts.length === 0) return null;
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(pts.flat()), 3));
      return geo;
    });
  }, [points]);

  useEffect(() => {
    const current = bands;
    return () => { current.forEach((g) => g?.dispose()); };
  }, [bands]);

  return (
    <group>
      {bands[0] && (
        <points geometry={bands[0]}>
          <pointsMaterial sizeAttenuation={false} size={3} color="#3a4760" map={texture || undefined} transparent opacity={0.35} depthWrite={false} />
        </points>
      )}
      {bands[1] && (
        <points geometry={bands[1]}>
          <pointsMaterial sizeAttenuation={false} size={3.5} color="#5d79a8" map={texture || undefined} transparent opacity={0.45} depthWrite={false} />
        </points>
      )}
      {bands[2] && (
        <points geometry={bands[2]}>
          <pointsMaterial sizeAttenuation={false} size={4} color="#9cc4ff" map={texture || undefined} transparent opacity={0.55} depthWrite={false} />
        </points>
      )}
    </group>
  );
};

// Nube de jugadores 3D: cada ghost en su posición REAL (incluye altura/piso),
// coloreado por FPS — rojo (<30) → ámbar (30-50) → verde (>50). Esto es la
// "data 3D" propiamente: muestra dónde estuvieron los jugadores en el espacio,
// no la agregación 2D de las torres de severidad.
const GhostCloud: React.FC<{ points: GhostPoint[] }> = ({ points }) => {
  const geometry = useMemo(() => {
    const g = new THREE.BufferGeometry();
    const n = points.length;
    const pos = new Float32Array(n * 3);
    const col = new Float32Array(n * 3);
    const c = new THREE.Color();
    for (let i = 0; i < n; i++) {
      const p = points[i];
      pos[i * 3] = p.x;
      pos[i * 3 + 1] = p.y;
      pos[i * 3 + 2] = p.z;
      const hex = p.fps >= 50 ? 0x3fb950 : p.fps >= 30 ? 0xd29922 : 0xf85149;
      c.setHex(hex);
      col[i * 3] = c.r;
      col[i * 3 + 1] = c.g;
      col[i * 3 + 2] = c.b;
    }
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    g.setAttribute('color', new THREE.BufferAttribute(col, 3));
    return g;
  }, [points]);

  if (points.length === 0) return null;
  return (
    <points geometry={geometry}>
      <pointsMaterial vertexColors size={3} sizeAttenuation={false} transparent opacity={0.85} depthWrite={false} />
    </points>
  );
};

const HotzoneMarkers: React.FC<{
  hotzones: HotzoneMarker[];
  scale: number;
  expandedId: string | null;
  onToggleExpand: (id: string | null) => void;
  onSelect?: (hz: HotzoneMarker) => void;
  onDownload?: (hz: HotzoneMarker) => void;
}> = ({ hotzones, scale, expandedId, onToggleExpand, onSelect, onDownload }) => {
  const [hovered, setHovered] = useState<string | null>(null);

  // Pins are sized relative to the scene so they stay visible from Dome_Crio's
  // ~70u up to OdiseaExterior's ~2000u without dwarfing or vanishing.
  const s = scale;

  const formatDate = (ts?: number | null) => {
    if (!ts) return '';
    return new Date(ts * 1000).toLocaleString('es', {
      day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit'
    });
  };

  return (
    <group>
      {hotzones.map((hz) => {
        if (hz.grid_x == null || hz.grid_z == null) return null;
        const x = hz.grid_x;
        const z = hz.grid_z;
        const isHover = hovered === hz.id;
        const isExpanded = expandedId === hz.id;

        return (
          <group key={hz.id} position={[x, 0, z]}>
            <mesh
              position={[0, 5 * s, 0]}
              onPointerOver={(e) => { e.stopPropagation(); setHovered(hz.id); }}
              onPointerOut={() => setHovered(null)}
              onClick={(e) => {
                e.stopPropagation();
                onToggleExpand(isExpanded ? null : hz.id);
              }}
            >
              <coneGeometry args={[s, 2 * s, 4]} />
              <meshStandardMaterial
                color={isExpanded ? "#ffffff" : "#ff3df0"}
                emissive={isExpanded ? "#ffffff" : "#ff3df0"}
                emissiveIntensity={isHover || isExpanded ? 0.8 : 0.4}
              />
            </mesh>
            <mesh position={[0, 5 * s, 0]} rotation={[0, Math.PI / 4, 0]}>
              <ringGeometry args={[1.3 * s, 1.8 * s, 4]} />
              <meshBasicMaterial color="#ff3df0" transparent opacity={0.5} side={THREE.DoubleSide} />
            </mesh>

            {/* Simple Hover Tooltip (hidden when expanded) */}
            {isHover && !isExpanded && (
              <Html distanceFactor={20} position={[0, 7 * s, 0]}>
                <div className="pointer-events-none whitespace-nowrap rounded border border-[#ff3df0]/50 bg-[#0c0e12]/95 px-2 py-1 text-[0.6rem] text-white shadow-xl">
                  <span className="font-bold text-[#ff3df0]">{hz.display_name || hz.player_id || 'hotzone'}</span>
                  {' · '}{hz.trigger_type || 'auto'}
                </div>
              </Html>
            )}

            {/* Detailed Expanded Panel */}
            {isExpanded && (
              <Html distanceFactor={25} position={[0, 8 * s, 0]} center>
                <div className="w-56 overflow-hidden rounded border border-[#ff3df0]/50 bg-[#0c0e12]/98 text-white shadow-2xl animate-in fade-in zoom-in-95 duration-200">
                  <div className="flex items-center justify-between border-b border-[#ff3df0]/20 bg-[#ff3df0]/10 px-3 py-2">
                    <div className="min-w-0">
                      <div className="truncate text-[0.7rem] font-black text-[#ff3df0]">
                        {hz.display_name || 'Anónimo'}
                      </div>
                      <div className="truncate font-mono text-[0.5rem] opacity-60">
                        {hz.player_id?.slice(0, 12)}
                      </div>
                    </div>
                    <button
                      onClick={(e) => { e.stopPropagation(); onToggleExpand(null); }}
                      className="text-text-muted hover:text-white"
                    >
                      <X size={14} />
                    </button>
                  </div>

                  <div className="p-3">
                    <div className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-[0.6rem]">
                      <span className="text-text-muted">Fecha</span>
                      <span className="text-right">{formatDate(hz.timestamp)}</span>
                      <span className="text-text-muted">Trigger</span>
                      <span className={`text-right font-bold ${hz.trigger_type === 'manual' ? 'text-accent' : 'text-danger'}`}>
                        {hz.trigger_type}
                      </span>
                      {hz.size_kb && (
                        <>
                          <span className="text-text-muted">Tamaño</span>
                          <span className="text-right">{hz.size_kb} KB</span>
                        </>
                      )}
                      {hz.capture_duration && (
                        <>
                          <span className="text-text-muted">Duración</span>
                          <span className="text-right">{hz.capture_duration.toFixed(1)}s</span>
                        </>
                      )}
                      {hz.frame_count && (
                        <>
                          <span className="text-text-muted">Frames</span>
                          <span className="text-right">{hz.frame_count}</span>
                        </>
                      )}
                    </div>

                    <div className="mt-4 flex gap-2">
                      <button
                        onClick={(e) => { e.stopPropagation(); onSelect?.(hz); }}
                        className="flex flex-1 items-center justify-center gap-1.5 rounded border border-success bg-success/10 py-1.5 text-[0.6rem] font-bold text-success hover:bg-success hover:text-black transition-colors"
                      >
                        <Play size={12} fill="currentColor" /> REPLAY
                      </button>
                      <button
                        onClick={(e) => { e.stopPropagation(); onDownload?.(hz); }}
                        className="flex flex-1 items-center justify-center gap-1.5 rounded border border-accent bg-accent/10 py-1.5 text-[0.6rem] font-bold text-accent hover:bg-accent hover:text-black transition-colors"
                      >
                        <Download size={12} /> Bajar
                      </button>
                    </div>
                  </div>
                </div>
              </Html>
            )}
          </group>
        );
      })}
    </group>
  );
};

export const Heatmap3D: React.FC<Heatmap3DProps> = ({ data, resolution, scene, hotzones, ghosts, onSelectHotzone, onDownloadHotzone }) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [hoveredCell, setHoveredCell] = useState<HeatmapCell | null>(null);
  const [selectedCell, setSelectedCell] = useState<HeatmapCell | null>(null);
  const [expandedHotzoneId, setExpandedHotzoneId] = useState<string | null>(null);
  const [controlsOpen, setControlsOpen] = useState(true);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const cells = Array.isArray(data) ? data : [];
  const maxCount = useMemo(() => cells.reduce((m, c) => Math.max(m, c.count), 0), [cells]);

  // Center + extent of the heat data alone — stable (doesn't depend on points),
  // so it's safe to feed to the streaming geometry as the focus position.
  const { center, radius } = useMemo(() => {
    let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
    for (const c of cells) {
      if (c.grid_x < minX) minX = c.grid_x; if (c.grid_x > maxX) maxX = c.grid_x;
      if (c.grid_z < minZ) minZ = c.grid_z; if (c.grid_z > maxZ) maxZ = c.grid_z;
    }
    if (!isFinite(minX)) return { center: [0, 0, 0] as [number, number, number], radius: 60 };
    const cx = (minX + maxX) / 2, cz = (minZ + maxZ) / 2;
    const r = Math.max(20, Math.hypot(maxX - minX, maxZ - minZ) / 2);
    return { center: [cx, 0, cz] as [number, number, number], radius: r };
  }, [cells]);

  // Same source as the live 3D viewport: stream the points near the heat center
  // instead of pulling the whole scene .json. Radius covers the heat spread.
  const { geometry } = useSceneGeometryStream(
    scene || '',
    center,
    Math.min(500, Math.max(120, radius * 1.6)),
  );
  const scenePoints = geometry?.points ?? [];

  // The panel shows the selected cell if one is pinned, else whatever is hovered.
  const panelCell = selectedCell || hoveredCell;

  const exportPng = () => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const link = document.createElement('a');
    link.setAttribute('download', `heatmap-${scene || 'scene'}-${Date.now()}.png`);
    link.setAttribute('href', canvas.toDataURL('image/png'));
    link.click();
  };

  const toggleFullscreen = () => {
    const el = containerRef.current;
    if (!el) return;
    if (!document.fullscreenElement) {
      el.requestFullscreen?.().then(() => setIsFullscreen(true)).catch(() => {});
    } else {
      document.exitFullscreen?.().then(() => setIsFullscreen(false)).catch(() => {});
    }
  };

  return (
    <div ref={containerRef} className="relative h-full w-full overflow-hidden rounded-lg border border-[#232833] bg-black">
      <Canvas
        ref={canvasRef}
        gl={{ preserveDrawingBuffer: true }}
        onPointerMissed={() => {
          setSelectedCell(null);
          setExpandedHotzoneId(null);
        }}
      >
        <PerspectiveCamera
          makeDefault
          position={[center[0] + radius * 0.9, radius * 1.1, center[2] + radius * 0.9]}
          far={Math.max(2000, radius * 8)}
        />
        <ambientLight intensity={0.7} />
        <directionalLight position={[10, radius, 5]} intensity={1} />
        <pointLight position={[center[0], radius * 0.8, center[2]]} intensity={0.4} />

        {scenePoints.length > 0 && (
          <SceneScatter points={scenePoints} />
        )}

        {ghosts && ghosts.length > 0 && <GhostCloud points={ghosts} />}

        {cells.map((cell, idx) => (
          <Cell
            key={idx}
            cell={cell}
            resolution={resolution}
            maxCount={maxCount}
            selected={selectedCell === cell}
            onHover={setHoveredCell}
            onSelect={setSelectedCell}
          />
        ))}

        {hotzones && hotzones.length > 0 && (
          <HotzoneMarkers
            hotzones={hotzones}
            scale={Math.max(0.9, radius * 0.02)}
            expandedId={expandedHotzoneId}
            onToggleExpand={setExpandedHotzoneId}
            onSelect={onSelectHotzone}
            onDownload={onDownloadHotzone}
          />
        )}

        <Grid
          infiniteGrid
          fadeDistance={Math.max(250, radius * 4)}
          cellColor="#232833"
          sectionColor="#2a3140"
          cellSize={resolution}
          sectionSize={resolution * 5}
          position={[0, 0.01, 0]}
        />

        <OrbitControls
          key={scene || 'heatmap'}
          target={[center[0], 0, center[2]]}
          enablePan
          makeDefault
        />
      </Canvas>

      {/* Fixed, readable stats panel (replaces the tiny floating 3D tooltip). */}
      {panelCell && (
        <div className="absolute bottom-4 left-4 w-56 rounded border border-[#232833] bg-[#0c0e12]/95 p-3 text-[0.7rem] text-white shadow-xl">
          <div className="mb-2 flex items-center justify-between border-b border-[#232833] pb-1">
            <span className="font-bold text-[#7fd1ff]">CELDA {panelCell.grid_x}, {panelCell.grid_z}</span>
            {selectedCell && (
              <button
                onClick={() => setSelectedCell(null)}
                className="text-[0.6rem] text-text-muted hover:text-white"
              >
                ✕
              </button>
            )}
          </div>
          <div className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1">
            <span className="text-text-muted">Frames</span>
            <span className="text-right">{panelCell.count}</span>
            <span className="text-text-muted">Low FPS (&lt;30)</span>
            <span className={`text-right ${lowFpsPct(panelCell) >= 30 ? 'text-red-400' : ''}`}>
              {panelCell.low_fps_count} ({lowFpsPct(panelCell).toFixed(1)}%)
            </span>
            <span className="text-text-muted">Avg FPS</span>
            <span className="text-right">{panelCell.avg_fps.toFixed(1)}</span>
            <span className="text-text-muted">Min FPS</span>
            <span className="text-right">{panelCell.min_fps.toFixed(1)}</span>
            <span className="text-text-muted">Avg Mem</span>
            <span className="text-right">{panelCell.avg_mem.toFixed(1)} MB</span>
          </div>
          {!selectedCell && (
            <div className="mt-2 text-[0.55rem] text-text-muted">Click para fijar</div>
          )}
        </div>
      )}

      {/* Collapsible control cluster (top-right). */}
      <div className="absolute right-4 top-4 flex flex-col items-end gap-2">
        <div className="flex gap-2">
          <button
            onClick={() => setControlsOpen((v) => !v)}
            className="rounded border border-[#232833] bg-[#0c0e12]/90 p-2 text-text-muted shadow-lg transition-colors hover:text-white"
            title={controlsOpen ? 'Ocultar controles' : 'Mostrar controles'}
            aria-label="Alternar controles"
          >
            {controlsOpen ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
          </button>
          <button
            onClick={toggleFullscreen}
            className="rounded border border-[#232833] bg-[#0c0e12]/90 p-2 text-text-muted shadow-lg transition-colors hover:text-white"
            title={isFullscreen ? 'Salir de pantalla completa' : 'Pantalla completa'}
            aria-label="Pantalla completa"
          >
            {isFullscreen ? <Minimize2 size={16} /> : <Maximize2 size={16} />}
          </button>
        </div>
        {controlsOpen && (
          <button
            onClick={exportPng}
            className="rounded bg-[#7fd1ff] px-4 py-2 text-xs font-bold text-black shadow-lg transition-colors hover:bg-[#7fd1ff]/80"
          >
            EXPORT PNG
          </button>
        )}
      </div>
    </div>
  );
};
