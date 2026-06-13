import React, { useMemo, useRef, useState, useCallback } from 'react';
import { useFrame } from '@react-three/fiber';
import { Html } from '@react-three/drei';
import * as THREE from 'three';
import type { ThreeEvent } from '@react-three/fiber';
import type { GeoPlayer } from '../../types';

export interface GroupedPlayer extends GeoPlayer {
  count: number;
  names: string[];
  pos: THREE.Vector3;
}

interface GeoDotsProps {
  players: GeoPlayer[];
  isMobile?: boolean;
  onSelect?: (group: GroupedPlayer | null) => void;
  selectedKey?: string | null;
}

function latLngToVec3(lat: number, lng: number, radius: number): THREE.Vector3 {
  const phi = (90 - lat) * (Math.PI / 180);
  const theta = (lng + 180) * (Math.PI / 180);
  return new THREE.Vector3(
    -radius * Math.sin(phi) * Math.cos(theta),
    radius * Math.cos(phi),
    radius * Math.sin(phi) * Math.sin(theta),
  );
}

export const GeoDots: React.FC<GeoDotsProps> = ({ players, isMobile, onSelect, selectedKey }) => {
  const meshRef = useRef<THREE.InstancedMesh>(null);
  const [hoveredIdx, setHoveredIdx] = useState<number | null>(null);

  const groupedPlayers = useMemo(() => {
    const groups: { [key: string]: GroupedPlayer } = {};
    players.forEach(p => {
      const key = `${p.latitude.toFixed(2)}|${p.longitude.toFixed(2)}`;
      if (!groups[key]) {
        groups[key] = { ...p, count: 0, names: [], status: 'old', pos: latLngToVec3(p.latitude, p.longitude, 1.01) };
      }
      groups[key].count++;
      if (p.display_name) groups[key].names.push(p.display_name);
      if (p.status === 'connected') groups[key].status = 'connected';
      else if (p.status === 'recent' && groups[key].status === 'old') groups[key].status = 'recent';
    });
    return Object.values(groups);
  }, [players]);

  const dummy = useMemo(() => new THREE.Object3D(), []);
  const color = useMemo(() => new THREE.Color(), []);
  const appearanceTimeRef = useRef<{ [key: string]: number }>({});

  useFrame((state) => {
    if (!meshRef.current) return;
    const time = state.clock.getElapsedTime();

    groupedPlayers.forEach((p, i) => {
      const key = `${p.latitude}|${p.longitude}`;
      if (appearanceTimeRef.current[key] === undefined) appearanceTimeRef.current[key] = time;
      const fadeIn = Math.min(1, (time - appearanceTimeRef.current[key]) / 1.0);

      let scale = 1.0;
      if (p.status === 'connected') {
        scale = 1.0 + Math.sin(time * 5) * 0.2;
        color.set('#3fb950');
      } else if (p.status === 'recent') {
        scale = 1.0 + Math.sin(time * 2) * 0.1;
        color.set('#d29922');
      } else {
        color.set('#8b949e');
      }

      // Bigger base size on mobile for easier tapping
      const base = isMobile ? 0.032 : 0.015;
      const finalScale = (base + Math.min(p.count * 0.005, 0.05)) * scale * fadeIn;

      dummy.position.copy(p.pos);
      dummy.lookAt(p.pos.clone().multiplyScalar(2));
      dummy.scale.set(finalScale, finalScale, finalScale);
      dummy.updateMatrix();

      meshRef.current!.setMatrixAt(i, dummy.matrix);
      meshRef.current!.setColorAt(i, color);
    });

    meshRef.current.instanceMatrix.needsUpdate = true;
    if (meshRef.current.instanceColor) meshRef.current.instanceColor.needsUpdate = true;
  });

  const handleClick = useCallback((e: ThreeEvent<MouseEvent>) => {
    e.stopPropagation();
    const idx = e.instanceId;
    if (idx === undefined) return;
    const p = groupedPlayers[idx];
    if (!p) return;

    if (isMobile) {
      const key = `${p.latitude.toFixed(2)}|${p.longitude.toFixed(2)}`;
      if (selectedKey === key) {
        // Second tap on same dot: navigate
        if (p.player_id) window.location.search = `?player=${p.player_id}`;
      } else {
        onSelect?.(p);
      }
    } else {
      if (p.player_id) window.location.search = `?player=${p.player_id}`;
    }
  }, [groupedPlayers, isMobile, selectedKey, onSelect]);

  const tooltipPlayer = !isMobile && hoveredIdx !== null ? groupedPlayers[hoveredIdx] : null;

  return (
    <group>
      <instancedMesh
        ref={meshRef}
        args={[undefined, undefined, groupedPlayers.length]}
        onPointerOver={isMobile ? undefined : (e) => setHoveredIdx(e.instanceId!)}
        onPointerOut={isMobile ? undefined : () => setHoveredIdx(null)}
        onClick={handleClick}
      >
        <circleGeometry args={[1, 16]} />
        <meshBasicMaterial transparent opacity={0.8} side={THREE.DoubleSide} />
      </instancedMesh>

      {tooltipPlayer && (
        <Html position={tooltipPlayer.pos} pointerEvents="none">
          <div className="bg-black/80 border border-accent p-2 rounded text-[10px] whitespace-nowrap pointer-events-none select-none">
            <div className="font-bold">{tooltipPlayer.city}, {tooltipPlayer.country}</div>
            <div>{tooltipPlayer.count} jugadores</div>
          </div>
        </Html>
      )}
    </group>
  );
};
