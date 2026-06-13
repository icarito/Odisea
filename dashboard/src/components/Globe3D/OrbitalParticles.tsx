import React, { useRef, useMemo } from 'react';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';

const count = 100;
const INITIAL_PARTICLES = Array.from({ length: count }, () => ({
  radius: 1.1 + Math.random() * 0.3,
  phi: Math.random() * Math.PI * 2,
  theta: Math.random() * Math.PI,
  speed: 0.05 + Math.random() * 0.1
}));

export const OrbitalParticles: React.FC = () => {
  const meshRef = useRef<THREE.InstancedMesh>(null);
  const particlesRef = useRef(INITIAL_PARTICLES);
  const particles_data = particlesRef.current;

  const dummy = useMemo(() => new THREE.Object3D(), []);

  useFrame((_state, delta) => {
    if (!meshRef.current) return;

    particles_data.forEach((p, i) => {
      p.phi += p.speed * delta;

      const x = p.radius * Math.sin(p.theta) * Math.cos(p.phi);
      const y = p.radius * Math.cos(p.theta);
      const z = p.radius * Math.sin(p.theta) * Math.sin(p.phi);

      dummy.position.set(x, y, z);
      // Use state.clock.elapsedTime for stable pseudo-random scale if needed,
      // or just keep it constant for lint compliance if Math.random is forbidden in useFrame too.
      // Actually the error was in useMemo.
      dummy.scale.setScalar(0.007);
      dummy.updateMatrix();
      meshRef.current!.setMatrixAt(i, dummy.matrix);
    });
    meshRef.current.instanceMatrix.needsUpdate = true;
  });

  return (
    <instancedMesh ref={meshRef} args={[undefined, undefined, count]}>
      <sphereGeometry args={[1, 4, 4]} />
      <meshBasicMaterial color="#7fd1ff" transparent opacity={0.6} />
    </instancedMesh>
  );
};
