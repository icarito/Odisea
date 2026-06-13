import React from 'react';

export const GridLines: React.FC = () => {
  return (
    <mesh rotation={[Math.PI / 2, 0, 0]}>
      <sphereGeometry args={[1.001, 32, 16]} />
      <meshBasicMaterial
        color="#30363d"
        wireframe
        transparent
        opacity={0.3}
      />
    </mesh>
  );
};
