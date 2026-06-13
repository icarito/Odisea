import { useRef, useCallback, useEffect } from 'react';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';

export function useGlobeAnimation() {
  const groupRef = useRef<THREE.Group>(null);
  const autoRotateRef = useRef(true);
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
    };
  }, []);

  useFrame((_state, delta) => {
    if (groupRef.current && autoRotateRef.current) {
      // 0.15 rad/s as per spec
      groupRef.current.rotation.y += 0.15 * delta;
    }
  });

  const handleInteraction = useCallback(() => {
    autoRotateRef.current = false;
    if (timeoutRef.current) {
      clearTimeout(timeoutRef.current);
    }
    timeoutRef.current = setTimeout(() => {
      autoRotateRef.current = true;
    }, 5000); // 5 seconds of idle to resume rotation
  }, []);

  return {
    groupRef,
    handleInteraction
  };
}
