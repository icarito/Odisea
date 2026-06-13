import React from 'react';
import * as THREE from 'three';

export const Atmosphere: React.FC = () => {
  return (
    <mesh scale={[1.1, 1.1, 1.1]}>
      <sphereGeometry args={[1, 64, 64]} />
      <meshBasicMaterial
        color="#7fd1ff"
        transparent
        opacity={0.1}
        side={THREE.BackSide}
      />
    </mesh>
  );
};
