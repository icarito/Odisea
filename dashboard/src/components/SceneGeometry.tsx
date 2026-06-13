import React, { useMemo } from 'react';
import * as THREE from 'three';
import type { SceneGeometryData } from '../hooks/useSceneGeometry';
import { useFrame } from '@react-three/fiber';
import { Html } from '@react-three/drei';

interface SceneGeometryProps {
  data: SceneGeometryData;
  focusPosition?: [number, number, number];
  showGeometry?: boolean;
  showProps?: boolean;
  showZones?: boolean;
}

const RotatorMesh: React.FC<{ position: [number, number, number], radius: number, name: string }> = ({ position, radius, name }) => {
  const meshRef = React.useRef<THREE.Mesh>(null);

  useFrame((state) => {
    if (meshRef.current) {
      meshRef.current.rotation.y = state.clock.getElapsedTime() * 0.3;
    }
  });

  var displayRadius = Math.min(radius * 0.01, 5);
  return (
    <group position={position}>
      <mesh ref={meshRef} rotation={[Math.PI / 2, 0, 0]}>
        <cylinderGeometry args={[displayRadius, displayRadius, 0.3, 32, 1, true]} />
        <meshStandardMaterial color="#7fd1ff" wireframe transparent opacity={0.4} side={THREE.DoubleSide} />
      </mesh>
      <Html distanceFactor={15} position={[0, displayRadius + 0.5, 0]}>
        <div className="bg-bg-card/80 text-accent text-[0.5rem] px-1 rounded whitespace-nowrap border border-accent/30">
          ROT: {name}
        </div>
      </Html>
    </group>
  );
};

export const SceneGeometry: React.FC<SceneGeometryProps> = ({
  data,
  focusPosition = [0, 0, 0],
  showGeometry = true,
  showProps = true,
  showZones = true
}) => {
  // Render streamed points in distance bands so the slice reads as scene volume,
  // not as a flat sparse scatter. The backend sends nearest-first, but banding
  // makes walls/floors around the player much easier to read.
  const pointBands = useMemo(() => {
    if (!data.points || data.points.length === 0) return [];
    const radius = Math.max(1, data.stream?.radius || 160);
    const nearSq = Math.pow(radius * 0.33, 2);
    const midSq = Math.pow(radius * 0.66, 2);
    const buckets: [number, number, number][][] = [[], [], []];
    const [fx, fy, fz] = focusPosition;

    data.points.forEach((point) => {
      const dx = point[0] - fx;
      const dy = point[1] - fy;
      const dz = point[2] - fz;
      const d2 = dx * dx + dy * dy + dz * dz;
      buckets[d2 <= nearSq ? 0 : d2 <= midSq ? 1 : 2].push(point);
    });

    return buckets.map((points) => {
      if (points.length === 0) return null;
      const geometry = new THREE.BufferGeometry();
      geometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array(points.flat()), 3));
      return geometry;
    });
  }, [data.points, data.stream?.radius, focusPosition]);

  return (
    <group>
      {/* 1. Point Cloud Geometry */}
      {showGeometry && pointBands[2] && (
        <points geometry={pointBands[2]}>
          <pointsMaterial size={0.55} color="#3b4658" transparent opacity={0.55} depthWrite={false} />
        </points>
      )}
      {showGeometry && pointBands[1] && (
        <points geometry={pointBands[1]}>
          <pointsMaterial size={0.9} color="#4f9dff" transparent opacity={0.62} depthWrite={false} />
        </points>
      )}
      {showGeometry && pointBands[0] && (
        <points geometry={pointBands[0]}>
          <pointsMaterial size={1.35} color="#b8f3ff" transparent opacity={0.9} depthWrite={false} />
        </points>
      )}

      {/* 2. Zones */}
      {showZones && data.zones.map((zone, i) => {
        const sizeX = zone.bounds.max[0] - zone.bounds.min[0];
        const sizeY = zone.bounds.max[1] - zone.bounds.min[1];
        const sizeZ = zone.bounds.max[2] - zone.bounds.min[2];
        return (
          <mesh key={`zone-${i}`} position={zone.position}>
            <boxGeometry args={[sizeX, sizeY, sizeZ]} />
            <meshStandardMaterial color="#3182ce" wireframe transparent opacity={0.2} />
            <Html distanceFactor={20} position={[0, sizeY/2 + 0.5, 0]}>
                <div className="bg-blue-900/40 text-blue-200 text-[0.4rem] px-1 rounded whitespace-nowrap">
                    {zone.name}
                </div>
            </Html>
          </mesh>
        );
      })}

      {/* 3. Props & Rotators */}
      {showProps && data.props.map((prop, i) => {
        if (prop.type === 'rotator') {
          return <RotatorMesh key={`rot-${i}`} position={prop.position} radius={prop.radius || 190} name={prop.name} />;
        }

        const isInteractable = prop.tags.includes('interactable');
        const isHazard = prop.tags.includes('hazard');
        const color = isInteractable ? '#ed8936' : (isHazard ? '#f56565' : '#718096');

        return (
          <mesh key={`prop-${i}`} position={prop.position}>
            <boxGeometry args={[1, 1, 1]} />
            <meshStandardMaterial color={color} />
            <Html distanceFactor={10} position={[0, 1, 0]}>
                <div className="bg-bg-card/90 text-white text-[0.45rem] px-1 rounded border border-white/20 whitespace-nowrap opacity-0 hover:opacity-100 transition-opacity">
                    {prop.name}
                </div>
            </Html>
          </mesh>
        );
      })}
    </group>
  );
};
