import React, { useRef, Suspense, useEffect } from 'react';
import { Canvas } from '@react-three/fiber';
import { OrbitControls, Grid, Line, PerspectiveCamera, useGLTF, Html } from '@react-three/drei';
import * as THREE from 'three';
import { SceneGeometry } from './SceneGeometry';
import { useSceneGeometryStream } from '../hooks/useSceneGeometry';
import { formatFpsLabel } from '../lib/filters';

// Inline heatmap overlay rendered as a group so it can nest inside this Canvas.
// (The standalone Heatmap3D component owns its own Canvas and is used in the heatmap tab.)
const HeatmapOverlay: React.FC<{ data: any[]; resolution: number }> = ({ data, resolution }) => {
  return (
    <group>
      {data.map((cell, i) => {
        const x = cell.grid_x ?? cell.cell_x ?? 0;
        const z = cell.grid_z ?? cell.cell_z ?? 0;
        const lowPct = cell.count ? (cell.low_fps_count / cell.count) * 100 : 0;
        let color = '#22c55e';
        if (lowPct >= 50) color = '#ef4444';
        else if (lowPct >= 30) color = '#f97316';
        else if (lowPct >= 10) color = '#eab308';
        return (
          <mesh
            key={i}
            position={[x + resolution / 2, 0.05, z + resolution / 2]}
            rotation={[-Math.PI / 2, 0, 0]}
          >
            <planeGeometry args={[resolution * 0.95, resolution * 0.95]} />
            <meshStandardMaterial color={color} transparent opacity={0.5} side={THREE.DoubleSide} />
          </mesh>
        );
      })}
    </group>
  );
};

// Godot and Three.js both use Y-up, -Z=forward coordinate systems.
// Position data passes through directly — no axis conversion needed.
// Yaw is negated to match Godot's Basis(Vector3.UP, angle) to Three.js Euler Y rotation.
// Euler order is set to YXZ on the marker group to match camera orbit convention.

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
  heatmapData?: any[];
  liveGhosts?: any[];
  // Tag/name + color for the active (followed) player marker, so it shows its
  // label and custom color in 3D just like the ghost markers do.
  label?: string;
  color?: string;
  // Optional compact HUD overlaid in the corner (fps + position), used in the
  // full-space mobile/fullscreen view so the data doesn't steal canvas space.
  hud?: {
    fps?: number;
    scene?: string;
    playerId?: string;
    displayName?: string;
    sessionId?: string;
    platform?: string;
    memoryMb?: number;
    mode?: string;
    tick?: number;
    peers?: number;
    staleAge?: number;
  } | null;
  onUserInteract?: () => void;
  // History integration
  activeId?: string | null;
  heartbeats?: any;
  hotzones?: any[];
  sessions?: any[];
  onSelectSession?: (session: any) => void;
  onDownloadHotzone?: (id: string, label: string) => void;
  onPlayHotzone?: (id: string) => void;
  onTagPlayer?: (pid: string) => void;
  setActiveTab?: (tab: string) => void;
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

const PlayerMarker: React.FC<{ position: [number, number, number], yaw: number, pitch: number, roll: number, staleAge: number, label?: string, color?: string }> = ({ position, yaw, pitch, roll, staleAge, label, color = "#7fd1ff" }) => {
  const meshRef = useRef<THREE.Group>(null);
  const alpha = staleAge > 2 ? 0.3 : 1.0;

  return (
    <group position={new THREE.Vector3(...position)} rotation={[pitch, -yaw, roll, 'YXZ']} ref={meshRef}>
      {label && (
        <Html distanceFactor={10} position={[0, 1.5, 0]}>
          <div className="bg-bg-card/80 text-white text-[0.5rem] px-1 rounded whitespace-nowrap border border-border-custom">
            {label}
          </div>
        </Html>
      )}
      <mesh>
        <sphereGeometry args={[0.5, 16, 16]} />
        <meshStandardMaterial color={color} transparent opacity={alpha} />
      </mesh>
      <mesh position={[0, 0, -0.7]} rotation={[Math.PI / 2, 0, 0]}>
        <coneGeometry args={[0.2, 0.5, 8]} />
        <meshStandardMaterial color={color} transparent opacity={alpha} />
      </mesh>
    </group>
  );
};

export const Viewport3D: React.FC<Viewport3DProps> = ({
  position, yaw, pitch, roll, trail, follow, wireframe, sceneName, staleAge,
  heatmapData, liveGhosts, label, color, hud, onUserInteract,
  activeId, heartbeats, hotzones, sessions, onSelectSession, onDownloadHotzone, onPlayHotzone, onTagPlayer, setActiveTab
}) => {
  const cameraRef = useRef<THREE.PerspectiveCamera>(null);
  const controlsRef = useRef<any>(null);
  const { geometry, loading: geometryLoading, error: geometryError } = useSceneGeometryStream(sceneName, position);
  const geometrySummary = geometry
    ? `${geometry.points?.length ?? 0}/${geometry.stream?.total_points ?? geometry.metadata?.point_count ?? 0} pts · r${geometry.stream?.radius ?? 0}`
    : geometryLoading
      ? 'loading geometry'
      : geometryError
        ? 'geometry unavailable'
        : 'no geometry';

  const resetView = () => {
    if (cameraRef.current && controlsRef.current) {
      const target = follow ? new THREE.Vector3(...position) : new THREE.Vector3(0, 0, 0);
      cameraRef.current.position.copy(target.clone().add(new THREE.Vector3(15, 15, 15)));
      controlsRef.current.target.copy(target);
      controlsRef.current.update();
    }
  };

  // Force OrbitControls to track the new target when follow/position changes
  useEffect(() => {
    if (controlsRef.current && follow) {
      const target = new THREE.Vector3(...position);
      if (cameraRef.current && cameraRef.current.position.distanceTo(target) > 80) {
        cameraRef.current.position.copy(target.clone().add(new THREE.Vector3(15, 15, 15)));
      }
      controlsRef.current.target.lerp(target, 0.3);
      controlsRef.current.update();
    }
  }, [position, follow]);

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
                {geometry && <SceneGeometry data={geometry} focusPosition={position} showGeometry={!wireframe} />}
            </Suspense>
        </SceneErrorBoundary>

        <PlayerMarker position={position} yaw={yaw} pitch={pitch} roll={roll} staleAge={staleAge} label={label} color={color} />

        {liveGhosts?.map(ghost => (
          <PlayerMarker
            key={ghost.player_id}
            position={ghost.player?.position || [0,0,0]}
            yaw={ghost.player?.yaw || 0}
            pitch={ghost.player?.pitch || 0}
            roll={ghost.player?.roll || 0}
            staleAge={(Date.now() - (ghost.timestamp * 1000)) / 1000}
            label={ghost.display_name || ghost.player_id.slice(0,8)}
            color={ghost.color || (ghost.player?.fps < 30 ? "#ef4444" : ghost.player?.fps < 45 ? "#eab308" : "#22c55e")}
          />
        ))}

        {heatmapData && <HeatmapOverlay data={heatmapData} resolution={5} />}

        {trail.length > 1 && (
          <Line
            points={trail.map(p => new THREE.Vector3(Number(p[0]), Number(p[1]), Number(p[2])))}
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
            target={follow ? new THREE.Vector3(...position) : undefined}
            onStart={onUserInteract}
        />
      </Canvas>

      <div className="absolute top-4 left-4 flex flex-col gap-2 pointer-events-none">
        <div className="bg-bg-card/90 px-3 py-1.5 rounded text-[0.625rem] border border-border-custom pointer-events-auto">
            SCENE: <span className="text-accent font-bold">{sceneName || 'NONE'}</span>
        </div>
        <div
          className={`bg-bg-card/90 px-3 py-1.5 rounded text-[0.625rem] border pointer-events-auto ${
            geometryError ? 'border-danger text-danger' : geometry ? 'border-success text-success' : 'border-border-custom text-text-muted'
          }`}
          title={geometryError || undefined}
        >
          GEOM: <span className="font-bold">{geometrySummary}</span>
        </div>
        <button
            onClick={resetView}
            className="bg-bg-card/90 px-3 py-1.5 rounded text-[0.625rem] border border-border-custom hover:bg-bg-primary pointer-events-auto text-left"
        >
            RESET VIEW (CENITAL)
        </button>
      </div>

      {/* Session Hotzones Overlay */}
      {activeId && heartbeats?.[activeId] && hotzones && sessions && setActiveTab && onSelectSession && (
        <div className="absolute top-4 right-4 z-10 w-72 max-w-[40vw] flex flex-col gap-2 pointer-events-auto">
          <div className="bg-bg-card/90 border-2 border-black p-3 shadow-[2px_2px_0px_0px_black]">
            <div className="flex justify-between items-center mb-2">
              <span className="text-[0.625rem] font-black uppercase text-accent">Session History</span>
              <button
                onClick={() => {
                  const hb = heartbeats[activeId];
                  const session = sessions.find(s => s.session_id === hb.session_id);
                  if (session) {
                    onSelectSession(session);
                    setActiveTab('history');
                  }
                }}
                className="text-[0.5rem] font-black uppercase bg-accent text-black px-1.5 py-0.5 hover:bg-white"
              >
                Go to History
              </button>
            </div>

            <div className="flex flex-col gap-1 max-h-48 overflow-y-auto pr-1">
              {(() => {
                const hb = heartbeats[activeId];
                const sessionHotzones = hotzones.filter(hz => hz.session_id === hb.session_id);
                if (sessionHotzones.length === 0) {
                  return <div className="text-[0.5rem] italic text-text-muted">No hotzones for this session</div>;
                }
                return sessionHotzones.map(hz => (
                  <div key={hz.id} className="flex items-center justify-between gap-1 border border-black bg-bg-primary px-2 py-1 text-[0.5rem]">
                    <div className="min-w-0 flex-1">
                      <div className="truncate font-black text-accent">{hz.scene}</div>
                      <div className="text-text-muted">
                        {hz.trigger_type || 'auto'} · {Math.round(hz.capture_duration || 0)}s
                      </div>
                    </div>
                    <div className="flex gap-1 shrink-0">
                      {onPlayHotzone && (
                        <button onClick={() => onPlayHotzone(hz.id)} className="text-success hover:scale-110">Play</button>
                      )}
                      {onDownloadHotzone && (
                        <button onClick={() => onDownloadHotzone(hz.id, label || activeId)} className="text-accent hover:scale-110">DL</button>
                      )}
                    </div>
                  </div>
                ));
              })()}
            </div>
          </div>
        </div>
      )}

      {/* Compact data HUD (doesn't steal canvas space). */}
      {hud && (
        <div className="absolute bottom-3 right-3 pointer-events-none w-56 bg-black/65 px-3 py-2 rounded text-[10px] font-mono leading-tight text-white">
          <div className="mb-1 flex items-center justify-between gap-2 border-b border-white/15 pb-1">
            <span className="truncate text-accent font-bold">{hud.displayName || hud.playerId?.slice(0, 8) || 'PLAYER'}</span>
            <span className={(hud.fps ?? 0) < 30 ? 'text-danger' : (hud.fps ?? 0) < 45 ? 'text-warning' : 'text-success'}>
              {formatFpsLabel(hud.fps ?? 0)}
            </span>
          </div>
          <div className="grid grid-cols-[4.5rem_minmax(0,1fr)] gap-x-2 gap-y-0.5">
            <span className="text-text-muted">Scene</span>
            <span className="truncate text-accent">{hud.scene || sceneName || '-'}</span>
            <span className="text-text-muted">Session</span>
            <span className="truncate">{hud.sessionId?.slice(0, 10) || '-'}</span>
            <span className="text-text-muted">Platform</span>
            <span className="uppercase">{hud.platform || '-'}</span>
            <span className="text-text-muted">Mode</span>
            <span className="truncate">{hud.mode || '-'}</span>
            <span className="text-text-muted">Memory</span>
            <span>{hud.memoryMb != null ? `${hud.memoryMb.toFixed(0)} MB` : '-'}</span>
            <span className="text-text-muted">Peers</span>
            <span>{hud.peers ?? 0}</span>
            <span className="text-text-muted">Tick</span>
            <span>{hud.tick ?? '-'}</span>
            <span className="text-text-muted">Stale</span>
            <span>{hud.staleAge != null ? `${hud.staleAge.toFixed(1)}s` : '-'}</span>
            <span className="text-text-muted">Position</span>
            <span className="truncate">{position.map(n => n.toFixed(1)).join(', ')}</span>
          </div>
        </div>
      )}
    </div>
  );
};
