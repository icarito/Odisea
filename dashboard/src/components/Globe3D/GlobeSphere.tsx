import React from 'react';

export const GlobeSphere: React.FC<{ isMobile?: boolean }> = ({ isMobile }) => {
  const segments = isMobile ? 32 : 64;
  return (
    <group>
      {/* Surface */}
      <mesh>
        <sphereGeometry args={[1, segments, segments]} />
        <meshStandardMaterial
          color="#0d1117"
          roughness={0.7}
          metalness={0.2}
          emissive="#161b22"
          emissiveIntensity={0.5}
        />
      </mesh>

      {/* Subtle Wireframe */}
      <mesh scale={[1.002, 1.002, 1.002]}>
        <sphereGeometry args={[1, 32, 32]} />
        <meshBasicMaterial
          color="#7fd1ff"
          wireframe
          transparent
          opacity={0.05}
        />
      </mesh>
    </group>
  );
};
