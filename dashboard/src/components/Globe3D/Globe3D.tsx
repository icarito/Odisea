import React, { Suspense } from 'react';
import { Canvas, useThree } from '@react-three/fiber';
import { OrbitControls, PerspectiveCamera } from '@react-three/drei';
import { Starfield } from './Starfield';
import { Atmosphere } from './Atmosphere';
import { GridLines } from './GridLines';
import { GlobeSphere } from './GlobeSphere';
import { OrbitalParticles } from './OrbitalParticles';
import { GeoDots } from './GeoDots';
import { useGlobeAnimation } from './useGlobeAnimation';
import type { GeoPlayer } from '../../types';

interface Globe3DProps {
  players: GeoPlayer[];
}

const GlobeScene: React.FC<Globe3DProps> = ({ players }) => {
  const { groupRef, handleInteraction } = useGlobeAnimation();
  const { size } = useThree();
  const isMobile = size.width < 768;

  return (
    <>
      <PerspectiveCamera makeDefault position={[0, 0, 3]} fov={45} />
      <OrbitControls
        enablePan={false}
        minDistance={1.5}
        maxDistance={6}
        rotateSpeed={0.5}
        zoomSpeed={0.8}
        onChange={handleInteraction}
      />

      <ambientLight intensity={0.5} />
      <pointLight position={[10, 10, 10]} intensity={1} />

      <Starfield />

      <group ref={groupRef}>
        <GlobeSphere isMobile={isMobile} />
        <GridLines />
        <GeoDots players={players} />
        {!isMobile && <OrbitalParticles />}
      </group>

      <Atmosphere />
    </>
  );
};

export const Globe3D: React.FC<Globe3DProps> = ({ players }) => {
  return (
    <div className="h-full w-full bg-[#080a0f]">
      <Canvas
        shadows
        gl={{ antialias: true, alpha: true }}
      >
        <Suspense fallback={null}>
          <GlobeScene players={players} />
        </Suspense>
      </Canvas>
    </div>
  );
};
