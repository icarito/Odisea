import React, { useMemo } from 'react';
import * as THREE from 'three';
import type { SceneGeometryData } from '../hooks/useSceneGeometry';
import { useFrame } from '@react-three/fiber';
import { Html } from '@react-three/drei';

interface SceneGeometryProps {
  data: SceneGeometryData;
  showGeometry?: boolean;
  showProps?: boolean;
  showZones?: boolean;
}

const RotatorMesh: React.FC<{ position: [number, number, number], radius: number, name: string }> = ({ position, radius, name }) => {
  const meshRef = React.useRef<THREE.Mesh>(null);

  useFrame((state) => {
    if (meshRef.current) {
      meshRef.current.rotation.y = state.clock.getElapsedTime() * 0.5;
    }
  });

  return (
    <mesh ref={meshRef} position={position}>
      <cylinderGeometry args={[radius, radius, 2, 32, 1, true]} />
      <meshStandardMaterial color="#7fd1ff" wireframe transparent opacity={0.3} side={THREE.DoubleSide} />
      <Html distanceFactor={15} position={[0, radius * 0.1 + 1, 0]}>
        <div className="bg-bg-card/80 text-accent text-[0.5rem] px-1 rounded whitespace-nowrap border border-accent/30">
          ROTATOR: {name}
        </div>
      </Html>
    </mesh>
  );
};

export const SceneGeometry: React.FC<SceneGeometryProps> = ({
  data,
  showGeometry = true,
  showProps = true,
  showZones = true
}) => {
  // Use useMemo for geometry to avoid re-calculating every frame
  const pointsGeometry = useMemo(() => {
    if (!data.points || data.points.length === 0) return null;
    const geometry = new THREE.BufferGeometry();
    const vertices = new Float32Array(data.points.flat());
    geometry.setAttribute('position', new THREE.BufferAttribute(vertices, 3));
    return geometry;
  }, [data.points]);

  return (
    <group>
      {/* 1. Point Cloud Geometry */}
      {showGeometry && pointsGeometry && (
        <points geometry={pointsGeometry}>
          <pointsMaterial size={0.3} color="#4a5568" transparent opacity={0.8} />
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
