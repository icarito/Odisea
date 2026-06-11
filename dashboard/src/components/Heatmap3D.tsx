import React, { useMemo } from 'react';
import * as THREE from 'three';

interface Heatmap3DProps {
  data: {
    cell_x: number;
    cell_z: number;
    count: number;
    low_fps_count: number;
    avg_fps: number;
    avg_mem: number;
  }[];
  resolution: number;
}

export const Heatmap3D: React.FC<Heatmap3DProps> = ({ data, resolution }) => {
  const cells = useMemo(() => {
    return data.map((d) => {
      const pctLow = (d.low_fps_count / d.count) * 100;
      let color = '#22c55e'; // Green
      if (pctLow > 50) color = '#ef4444'; // Red
      else if (pctLow > 30) color = '#f97316'; // Orange
      else if (pctLow > 10) color = '#eab308'; // Yellow

      return {
        pos: [d.cell_x, 0.1, d.cell_z] as [number, number, number],
        color,
        opacity: 0.6,
        data: d
      };
    });
  }, [data]);

  return (
    <group>
      {cells.map((cell, i) => (
        <mesh key={i} position={cell.pos} rotation={[-Math.PI / 2, 0, 0]}>
          <planeGeometry args={[resolution * 0.95, resolution * 0.95]} />
          <meshStandardMaterial
            color={cell.color}
            transparent
            opacity={cell.opacity}
            side={THREE.DoubleSide}
          />
        </mesh>
      ))}
    </group>
  );
};
