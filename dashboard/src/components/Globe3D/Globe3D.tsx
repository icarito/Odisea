import React, { Suspense, useState } from 'react';
import { Canvas, useThree } from '@react-three/fiber';
import { OrbitControls, PerspectiveCamera } from '@react-three/drei';
import * as THREE from 'three';
import { Starfield } from './Starfield';
import { Atmosphere } from './Atmosphere';
import { GridLines } from './GridLines';
import { GlobeSphere } from './GlobeSphere';
import { CountryBorders } from './CountryBorders';
import { OrbitalParticles } from './OrbitalParticles';
import { GeoDots } from './GeoDots';
import type { GroupedPlayer } from './GeoDots';
import { useGlobeAnimation } from './useGlobeAnimation';
import type { GeoPlayer } from '../../types';

interface Globe3DProps {
  players: GeoPlayer[];
}

interface GlobeSceneProps extends Globe3DProps {
  onSelect: (g: GroupedPlayer | null) => void;
  selectedKey: string | null;
}

const GlobeScene: React.FC<GlobeSceneProps> = ({ players, onSelect, selectedKey }) => {
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
        rotateSpeed={isMobile ? 0.9 : 0.5}
        zoomSpeed={0.8}
        enableDamping
        dampingFactor={0.12}
        onChange={handleInteraction}
        touches={{
          ONE: THREE.TOUCH.ROTATE,
          TWO: THREE.TOUCH.DOLLY_ROTATE,
        }}
      />

      <ambientLight intensity={0.5} />
      <pointLight position={[10, 10, 10]} intensity={1} />

      <Starfield />

      <group ref={groupRef} onClick={() => onSelect(null)}>
        <GlobeSphere isMobile={isMobile} />
        <CountryBorders />
        <GridLines />
        <GeoDots
          players={players}
          isMobile={isMobile}
          onSelect={onSelect}
          selectedKey={selectedKey}
        />
        {!isMobile && <OrbitalParticles />}
      </group>

      <Atmosphere />
    </>
  );
};

export const Globe3D: React.FC<Globe3DProps> = ({ players }) => {
  const [selected, setSelected] = useState<GroupedPlayer | null>(null);
  const selectedKey = selected
    ? `${selected.latitude.toFixed(2)}|${selected.longitude.toFixed(2)}`
    : null;

  return (
    <div className="h-full w-full bg-[#080a0f] relative">
      <Canvas
        shadows
        gl={{ antialias: true, alpha: true }}
        onPointerMissed={() => setSelected(null)}
      >
        <Suspense fallback={null}>
          <GlobeScene players={players} onSelect={setSelected} selectedKey={selectedKey} />
        </Suspense>
      </Canvas>

      {/* Mobile info overlay — shown on first tap, navigate on second */}
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
