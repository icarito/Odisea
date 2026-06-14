import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Canvas } from '@react-three/fiber';
import { OrbitControls, Grid, PerspectiveCamera, Html } from '@react-three/drei';
import * as THREE from 'three';
import { useSceneGeometry } from '../hooks/useSceneGeometry';

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
}

interface Heatmap3DProps {
  data: HeatmapCell[];
  resolution: number;
  scene?: string;
  hotzones?: HotzoneMarker[];
  onSelectHotzone?: (hz: HotzoneMarker) => void;
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
  const height = 0.4 + (pct / 100) * 6 + traffic * 2;

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

// Scene scatter cloud: the same point data the live viewport uses, drawn faded
// underneath the heat cells so the heatmap reads against real scene volume
// instead of an empty grid. Banded by distance from scene center for depth.
const SceneScatter: React.FC<{ points: [number, number, number][]; center: [number, number, number] }> = ({ points, center }) => {
  const texture = useMemo(() => {
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
  }, []);

  const bands = useMemo(() => {
    if (!points || points.length === 0) return [];
    let maxD = 1;
    for (const p of points) {
      const dx = p[0] - center[0], dy = p[1] - center[1], dz = p[2] - center[2];
      const d = Math.sqrt(dx * dx + dy * dy + dz * dz);
      if (d > maxD) maxD = d;
    }
    const near = maxD * 0.33, mid = maxD * 0.66;
    const buckets: [number, number, number][][] = [[], [], []];
    for (const p of points) {
      const dx = p[0] - center[0], dy = p[1] - center[1], dz = p[2] - center[2];
      const d = Math.sqrt(dx * dx + dy * dy + dz * dz);
      buckets[d <= near ? 0 : d <= mid ? 1 : 2].push(p);
    }
    return buckets.map((pts) => {
      if (pts.length === 0) return null;
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(pts.flat()), 3));
      return geo;
    });
  }, [points, center]);

  useEffect(() => {
    const current = bands;
    return () => { current.forEach((g) => g?.dispose()); };
  }, [bands]);

  return (
    <group>
      {bands[2] && (
        <points geometry={bands[2]}>
          <pointsMaterial size={0.3} color="#3a4760" map={texture || undefined} transparent opacity={0.22} depthWrite={false} />
        </points>
      )}
      {bands[1] && (
        <points geometry={bands[1]}>
          <pointsMaterial size={0.42} color="#4d6285" map={texture || undefined} transparent opacity={0.3} depthWrite={false} />
        </points>
      )}
      {bands[0] && (
        <points geometry={bands[0]}>
          <pointsMaterial size={0.55} color="#5d79a8" map={texture || undefined} transparent opacity={0.38} depthWrite={false} />
        </points>
      )}
    </group>
  );
};

const HotzoneMarkers: React.FC<{
  hotzones: HotzoneMarker[];
  onSelect?: (hz: HotzoneMarker) => void;
}> = ({ hotzones, onSelect }) => {
  const [hovered, setHovered] = useState<string | null>(null);
  return (
    <group>
      {hotzones.map((hz) => {
        if (hz.grid_x == null || hz.grid_z == null) return null;
        // grid_x/grid_z are world coords (resolution-agnostic) of the capture.
        const x = hz.grid_x;
        const z = hz.grid_z;
        const isHover = hovered === hz.id;
        return (
          <group key={hz.id} position={[x, 0, z]}>
            <mesh
              position={[0, 4.5, 0]}
              onPointerOver={(e) => { e.stopPropagation(); setHovered(hz.id); }}
              onPointerOut={() => setHovered(null)}
              onClick={(e) => { e.stopPropagation(); onSelect?.(hz); }}
            >
              <coneGeometry args={[0.9, 2, 4]} />
              <meshStandardMaterial color="#ff3df0" emissive="#ff3df0" emissiveIntensity={isHover ? 0.8 : 0.4} />
            </mesh>
            <mesh position={[0, 4.5, 0]} rotation={[0, Math.PI / 4, 0]}>
              <ringGeometry args={[1.2, 1.6, 4]} />
              <meshBasicMaterial color="#ff3df0" transparent opacity={0.5} side={THREE.DoubleSide} />
            </mesh>
            {isHover && (
              <Html distanceFactor={20} position={[0, 7, 0]}>
                <div className="pointer-events-none whitespace-nowrap rounded border border-[#ff3df0]/50 bg-[#0c0e12]/95 px-2 py-1 text-[0.6rem] text-white shadow-xl">
                  <span className="font-bold text-[#ff3df0]">{hz.display_name || hz.player_id || 'hotzone'}</span>
                  {' · '}{hz.trigger_type || 'auto'}
                </div>
              </Html>
            )}
          </group>
        );
      })}
    </group>
  );
};

export const Heatmap3D: React.FC<Heatmap3DProps> = ({ data, resolution, scene, hotzones, onSelectHotzone }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [hoveredCell, setHoveredCell] = useState<HeatmapCell | null>(null);
  const [selectedCell, setSelectedCell] = useState<HeatmapCell | null>(null);
  const { geometry } = useSceneGeometry(scene || '');

  const cells = Array.isArray(data) ? data : [];
  const maxCount = useMemo(() => cells.reduce((m, c) => Math.max(m, c.count), 0), [cells]);

  // Center the camera/scatter banding on the spread of the heat data so the
  // initial view frames the active area regardless of scene origin.
  const center = useMemo<[number, number, number]>(() => {
    if (cells.length === 0) return [0, 0, 0];
    let sx = 0, sz = 0;
    for (const c of cells) { sx += c.grid_x; sz += c.grid_z; }
    return [sx / cells.length, 0, sz / cells.length];
  }, [cells]);

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

  return (
    <div className="relative h-full w-full overflow-hidden rounded-lg border border-[#232833] bg-black">
      <Canvas ref={canvasRef} gl={{ preserveDrawingBuffer: true }} onPointerMissed={() => setSelectedCell(null)}>
        <PerspectiveCamera makeDefault position={[center[0] + 60, 60, center[2] + 60]} />
        <ambientLight intensity={0.7} />
        <directionalLight position={[10, 50, 5]} intensity={1} />
        <pointLight position={[center[0], 40, center[2]]} intensity={0.4} />

        {geometry?.points && geometry.points.length > 0 && (
          <SceneScatter points={geometry.points} center={center} />
        )}

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
          <HotzoneMarkers hotzones={hotzones} onSelect={onSelectHotzone} />
        )}

        <Grid
          infiniteGrid
          fadeDistance={250}
          cellColor="#232833"
          sectionColor="#2a3140"
          cellSize={resolution}
          sectionSize={resolution * 5}
          position={[0, 0.01, 0]}
        />

        <OrbitControls enablePan makeDefault target={new THREE.Vector3(center[0], 0, center[2])} />
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

      <div className="absolute right-4 top-4">
        <button
          onClick={exportPng}
          className="rounded bg-[#7fd1ff] px-4 py-2 text-xs font-bold text-black shadow-lg transition-colors hover:bg-[#7fd1ff]/80"
        >
          EXPORT PNG
        </button>
      </div>
    </div>
  );
};
