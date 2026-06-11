import React, { useRef, useState } from 'react';
import { Canvas } from '@react-three/fiber';
import { OrbitControls, Grid, PerspectiveCamera, Html } from '@react-three/drei';
import * as THREE from 'three';

interface HeatmapCell {
  grid_x: number;
  grid_z: number;
  count: number;
  low_fps_count: number;
  avg_fps: number;
  min_fps: number;
  avg_mem: number;
}

interface Heatmap3DProps {
  data: HeatmapCell[];
  resolution: number;
}

const Cell: React.FC<{ cell: HeatmapCell; resolution: number }> = ({ cell, resolution }) => {
  const [hovered, setHovered] = useState(false);

  const lowFpsPct = (cell.low_fps_count / cell.count) * 100;

  let color = '#22c55e'; // Green < 10%
  if (lowFpsPct >= 50) {
    color = '#ef4444'; // Red > 50%
  } else if (lowFpsPct >= 30) {
    color = '#f97316'; // Orange 30-50%
  } else if (lowFpsPct >= 10) {
    color = '#eab308'; // Yellow 10-30%
  }

  return (
    <group position={[cell.grid_x + resolution / 2, 0.01, cell.grid_z + resolution / 2]} rotation={[-Math.PI / 2, 0, 0]}>
      <mesh
        onPointerOver={(e) => { e.stopPropagation(); setHovered(true); }}
        onPointerOut={() => setHovered(false)}
      >
        <planeGeometry args={[resolution * 0.95, resolution * 0.95]} />
        <meshStandardMaterial
          color={color}
          transparent
          opacity={hovered ? 0.8 : 0.4}
          side={THREE.DoubleSide}
        />
      </mesh>
      {hovered && (
        <Html distanceFactor={15}>
          <div className="bg-[#0c0e12]/95 border border-[#232833] p-2 rounded text-[10px] whitespace-nowrap pointer-events-none shadow-xl z-50 text-white">
            <div className="font-bold text-[#7fd1ff] mb-1">
              GRID: {cell.grid_x}, {cell.grid_z}
            </div>
            <div>Total Frames: {cell.count}</div>
            <div className={lowFpsPct > 30 ? "text-red-400" : ""}>
              Low FPS (&lt;30): {cell.low_fps_count} ({lowFpsPct.toFixed(1)}%)
            </div>
            <div>Avg FPS: {cell.avg_fps.toFixed(1)}</div>
            <div>Min FPS: {cell.min_fps.toFixed(1)}</div>
            <div>Avg Mem: {cell.avg_mem.toFixed(1)} MB</div>
          </div>
        </Html>
      )}
    </group>
  );
};

export const Heatmap3D: React.FC<Heatmap3DProps> = ({ data, resolution }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  const exportPng = () => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const link = document.createElement('a');
    link.setAttribute('download', `heatmap-${new Date().getTime()}.png`);
    link.setAttribute('href', canvas.toDataURL('image/png'));
    link.click();
  };

  return (
    <div className="w-full h-full relative bg-black rounded-lg overflow-hidden border border-[#232833]">
      <Canvas
        ref={canvasRef}
        gl={{ preserveDrawingBuffer: true }}
      >
        <PerspectiveCamera makeDefault position={[50, 50, 50]} />
        <ambientLight intensity={0.7} />
        <directionalLight position={[10, 50, 5]} intensity={1} />

        {data.map((cell, idx) => (
          <Cell key={idx} cell={cell} resolution={resolution} />
        ))}

        <Grid
          infiniteGrid
          fadeDistance={200}
          cellColor="#232833"
          sectionColor="#2a3140"
          cellSize={resolution}
          sectionSize={resolution * 5}
        />

        <OrbitControls enablePan={true} makeDefault />
      </Canvas>

      <div className="absolute top-4 right-4">
        <button
          onClick={exportPng}
          className="bg-[#7fd1ff] hover:bg-[#7fd1ff]/80 text-black px-4 py-2 rounded text-xs font-bold transition-colors shadow-lg"
        >
          EXPORT PNG
        </button>
      </div>
    </div>
  );
};
