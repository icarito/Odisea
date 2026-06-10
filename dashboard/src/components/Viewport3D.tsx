import React, { useRef, Suspense, useEffect, useMemo } from 'react';
import { Canvas } from '@react-three/fiber';
import { OrbitControls, Grid, Line, PerspectiveCamera, useGLTF } from '@react-three/drei';
import * as THREE from 'three';

// Convert Godot coordinates (Y-up, X-forward, BACK=+Z) to Three.js (Y-up, FORWARD=-Z).
// Godot +Z = back, so invert Z. X stays as-is because Three.js default camera looks -Z.
const fromGodot = (gx: number, gy: number, gz: number): [number, number, number] =>
  [gx, gy, -gz];

interface Viewport3DProps {
  position: [number, number, number];
  yaw: number;
  pitch: number;
  roll: number;
  trail: [number, number, number][];
  follow: boolean;
  wireframe: boolean;
  sceneName: string;
  staleAge: number;
}

const SceneModel: React.FC<{ sceneName: string; wireframe: boolean }> = ({ sceneName, wireframe }) => {
  const url = `/game-assets/${sceneName}.glb`;

  // Resilient GLTF loading
  let scene;
  try {
    const gltf = useGLTF(url);
    scene = gltf.scene;
  } catch (e) {
    console.warn(`Failed to load level model: ${url}. Fallback to grid only.`);
    return null;
  }

  useEffect(() => {
    if (!scene) return;
    scene.traverse((child) => {
      if ((child as THREE.Mesh).isMesh) {
        const mesh = child as THREE.Mesh;
        if (mesh.material) {
          const materials = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
          materials.forEach((m: any) => {
            m.wireframe = wireframe;
            if (wireframe) {
                m.transparent = true;
                m.opacity = 0.3;
            } else {
                m.transparent = false;
                m.opacity = 1.0;
            }
          });
        }
      }
    });
  }, [scene, wireframe]);

  return <primitive object={scene} />;
};

// Error Boundary for R3F
class SceneErrorBoundary extends React.Component<{ children: React.ReactNode }, { hasError: boolean }> {
    constructor(props: any) {
        super(props);
        this.state = { hasError: false };
    }
    static getDerivedStateFromError() { return { hasError: true }; }
    componentDidCatch(error: any) { console.warn("R3F Error:", error); }
    render() {
        if (this.state.hasError) return null;
        return this.props.children;
    }
}

const PlayerMarker: React.FC<{ position: [number, number, number], yaw: number, pitch: number, roll: number, staleAge: number }> = ({ position, yaw, pitch, roll, staleAge }) => {
  const meshRef = useRef<THREE.Group>(null);
  const pos = useMemo(() => fromGodot(position[0], position[1], position[2]), [position]);
  const alpha = staleAge > 30 ? 0.3 : staleAge > 10 ? 0.55 : 1.0;

  return (
    <group position={new THREE.Vector3(...pos)} rotation={[pitch, -yaw, roll]} ref={meshRef}>
      <mesh>
        <sphereGeometry args={[0.5, 16, 16]} />
        <meshStandardMaterial color="#7fd1ff" transparent opacity={alpha} />
      </mesh>
      <mesh position={[0, 0, -0.7]} rotation={[Math.PI / 2, 0, 0]}>
        <coneGeometry args={[0.2, 0.5, 8]} />
        <meshStandardMaterial color="#7fd1ff" transparent opacity={alpha} />
      </mesh>
    </group>
  );
};

export const Viewport3D: React.FC<Viewport3DProps> = ({ position, yaw, pitch, roll, trail, follow, wireframe, sceneName, staleAge }) => {
  const cameraRef = useRef<THREE.PerspectiveCamera>(null);
  const controlsRef = useRef<any>(null);
  const pos = useMemo(() => fromGodot(position[0], position[1], position[2]), [position]);

  const resetView = () => {
    if (cameraRef.current && controlsRef.current) {
      cameraRef.current.position.set(15, 15, 15);
      controlsRef.current.target.set(0, 0, 0);
      controlsRef.current.update();
    }
  };

  // Force OrbitControls to track the new target when follow/position changes
  useEffect(() => {
    if (controlsRef.current && follow) {
      controlsRef.current.target.lerp(new THREE.Vector3(...pos), 0.3);
      controlsRef.current.update();
    }
  }, [pos, follow]);

  return (
    <div className="w-full h-full relative bg-black rounded-lg overflow-hidden border border-border-custom">
      <Canvas>
        <PerspectiveCamera makeDefault position={[15, 15, 15]} ref={cameraRef} />
        <ambientLight intensity={0.7} />
        <directionalLight position={[10, 10, 5]} intensity={1} />
        <pointLight position={[-10, 5, -10]} intensity={0.5} />

        <SceneErrorBoundary>
            <Suspense fallback={null}>
                {sceneName && <SceneModel sceneName={sceneName} wireframe={wireframe} />}
            </Suspense>
        </SceneErrorBoundary>

        <PlayerMarker position={position} yaw={yaw} pitch={pitch} roll={roll} staleAge={staleAge} />

        {trail.length > 1 && (
          <Line
            points={trail.map(p => new THREE.Vector3(...fromGodot(Number(p[0]), Number(p[1]), Number(p[2]))))}
            color="#7fd1ff"
            lineWidth={2}
            transparent
            opacity={0.6}
          />
        )}

        <Grid infiniteGrid fadeDistance={100} cellColor="#232833" sectionColor="#2a3140" />

        {/* Ground plane for depth when GLB is missing */}
        <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, -0.05, 0]}>
          <planeGeometry args={[1000, 1000]} />
          <meshStandardMaterial color="#0c0e12" transparent opacity={0.4} />
        </mesh>

        <OrbitControls
            ref={controlsRef}
            enablePan={true}
            makeDefault
            target={follow ? new THREE.Vector3(...pos) : undefined}
        />
      </Canvas>

      <div className="absolute top-4 left-4 flex flex-col gap-2 pointer-events-none">
        <div className="bg-bg-card/90 px-3 py-1.5 rounded text-[10px] border border-border-custom pointer-events-auto">
            SCENE: <span className="text-accent font-bold">{sceneName || 'NONE'}</span>
        </div>
        <button
            onClick={resetView}
            className="bg-bg-card/90 px-3 py-1.5 rounded text-[10px] border border-border-custom hover:bg-bg-primary pointer-events-auto text-left"
        >
            RESET VIEW (CENITAL)
        </button>
      </div>
    </div>
  );
};
