import React, { useEffect, useRef, useState, useCallback } from 'react';
import { Plus, Minus, Crosshair, HelpCircle, LocateFixed } from 'lucide-react';

interface ActiveGhost {
  player_id: string;
  session_id: string;
  scene: string;
  pos_x: number;
  pos_y: number;
  pos_z: number;
  fps: number;
  last_seen: number;
  platform?: string | null;
  memory_mb?: number;
  mode?: string;
}

interface LiveMapProps {
  ghosts: ActiveGhost[];
  sceneName: string;
  onSelectGhost?: (playerId: string) => void;
  // The active player the camera follows (when follow is on).
  activePlayerId?: string;
}

type HitGhost = { ghost: ActiveGhost; x: number; y: number; dist: number };

const fpsColor = (fps: number) => (fps < 30 ? '#ef4444' : fps < 45 ? '#eab308' : '#22c55e');
const TRAIL_LIMIT = 90;

// Birdseye map. Two modes:
//  - single-scene (sceneName !== ''): a top-down world view. The grid is drawn
//    in world space (so it scrolls under the player), and the camera follows the
//    active player until the user pans.
//  - multi-plane (sceneName === ''): each scene rendered as an isometric plane,
//    stacked vertically. A global zoom scales/spreads all planes; zooming over
//    one plane focuses just that plane.
export const LiveMap: React.FC<LiveMapProps> = ({ ghosts, sceneName, onSelectGhost, activePlayerId }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const wrapRef = useRef<HTMLDivElement>(null);

  // Single-scene camera: world->screen = center + offset + worldPos*(baseScale*zoom).
  const camRef = useRef({ zoom: 1, offsetX: 0, offsetY: 0 });
  // Multi-plane global zoom (spreads + scales every plane together).
  const globalZoomRef = useRef(1);
  // Per-plane focus camera (zoom + local pan inside that plane).
  const planeCamsRef = useRef<Record<string, { zoom: number; offsetX: number; offsetY: number }>>({});
  // Vertical scroll for the stacked planes in multi-plane mode.
  const stackOffsetRef = useRef(0);
  // Camera follows the active player until the user pans (then released).
  const followRef = useRef(true);

  const [, forceTick] = useState(0); // re-render for the live counter
  const [showHelp, setShowHelp] = useState(false);
  const [hover, setHover] = useState<{ ghost: ActiveGhost; x: number; y: number } | null>(null);
  const trailsRef = useRef<Record<string, { scene: string; x: number; y: number; z: number }[]>>({});

  // Keep latest props in refs so the rAF loop reads fresh values.
  const ghostsRef = useRef(ghosts);
  const sceneRef = useRef(sceneName);
  const activeIdRef = useRef(activePlayerId);
  ghostsRef.current = ghosts;
  sceneRef.current = sceneName;
  activeIdRef.current = activePlayerId;

  const visible = ghosts.filter(g => sceneName === '' || g.scene === sceneName);

  useEffect(() => {
    ghosts.forEach((ghost) => {
      const trail = trailsRef.current[ghost.player_id] || [];
      const last = trail[trail.length - 1];
      const scene = ghost.scene || 'Unknown';
      if (last && last.scene !== scene) {
        trailsRef.current[ghost.player_id] = [{ scene, x: ghost.pos_x, y: ghost.pos_y, z: ghost.pos_z }];
        return;
      }
      if (!last || Math.hypot(last.x - ghost.pos_x, last.y - ghost.pos_y, last.z - ghost.pos_z) > 0.15) {
        trailsRef.current[ghost.player_id] = [...trail, { scene, x: ghost.pos_x, y: ghost.pos_y, z: ghost.pos_z }].slice(-TRAIL_LIMIT);
      }
    });
  }, [ghosts]);

  const sceneLayers = () => {
    const names: string[] = [];
    ghostsRef.current
      .filter(g => sceneRef.current === '' || g.scene === sceneRef.current)
      .forEach((ghost) => {
      const name = ghost.scene || 'Unknown';
      if (!names.includes(name)) names.push(name);
    });
    return names.sort();
  };

  const sceneCentroid = (scene: string) => {
    const list = ghostsRef.current.filter((ghost) => (ghost.scene || 'Unknown') === scene);
    if (list.length === 0) return { x: 0, z: 0 };
    return {
      x: list.reduce((sum, ghost) => sum + ghost.pos_x, 0) / list.length,
      z: list.reduce((sum, ghost) => sum + ghost.pos_z, 0) / list.length,
    };
  };

  const planeCam = (scene: string) => {
    if (!planeCamsRef.current[scene]) {
      planeCamsRef.current[scene] = { zoom: 1, offsetX: 0, offsetY: 0 };
    }
    return planeCamsRef.current[scene];
  };

  // Plane geometry scales with the global zoom and stacks vertically with extra
  // spacing so each plane is large and legible (uses more of the screen).
  const planeGeometry = (scene: string, width: number, height: number) => {
    const layers = sceneLayers();
    const layerIndex = Math.max(0, layers.indexOf(scene));
    const gz = globalZoomRef.current;
    const spacing = 300 * gz;
    const centerX = width / 2;
    const centerY = height / 2 + layerIndex * spacing + stackOffsetRef.current;
    const halfW = Math.min(560, Math.max(280, width * 0.42)) * gz;
    const halfD = 150 * gz;
    return {
      centerX,
      centerY,
      halfW,
      halfD,
      corners: [
        [centerX, centerY - halfD],
        [centerX + halfW, centerY],
        [centerX, centerY + halfD],
        [centerX - halfW, centerY],
      ] as [number, number][],
    };
  };

  const hitPlane = (clientX: number, clientY: number) => {
    const rect = canvasRef.current?.getBoundingClientRect();
    if (!rect || sceneRef.current !== '') return null;
    const x = clientX - rect.left;
    const y = clientY - rect.top;
    return sceneLayers().find((scene) => {
      const p = planeGeometry(scene, rect.width, rect.height);
      return Math.abs(x - p.centerX) / p.halfW + Math.abs(y - p.centerY) / p.halfD <= 1;
    }) || null;
  };

  const projectGhost = (ghost: Pick<ActiveGhost, 'scene' | 'pos_x' | 'pos_z'>, width: number, height: number) => {
    if (sceneName !== '') {
      const cam = camRef.current;
      const scale = 2 * cam.zoom;
      const cx = width / 2 + cam.offsetX;
      return {
        x: cx + ghost.pos_x * scale,
        y: height / 2 + cam.offsetY + ghost.pos_z * scale,
        layer: '',
        layerTop: 0,
        layerHeight: height,
      };
    }

    const layers = sceneLayers();
    const layerIndex = Math.max(0, layers.indexOf(ghost.scene || 'Unknown'));
    const layerName = layers[layerIndex] || ghost.scene || 'Unknown';
    const cam = planeCam(layerName);
    const center = sceneCentroid(layerName);
    const localX = ghost.pos_x - center.x;
    const localZ = ghost.pos_z - center.z;
    const planeZoom = Math.min(2.4, Math.max(0.65, cam.zoom)) * globalZoomRef.current;
    const p = planeGeometry(layerName, width, height);
    const layerTop = p.centerY - p.halfD;
    const isoX = (localX - localZ) * planeZoom * 1.15 + cam.offsetX;
    const isoY = (localX + localZ) * planeZoom * 0.58 + cam.offsetY;
    return {
      x: p.centerX + isoX,
      y: p.centerY + isoY,
      layer: layers[layerIndex] || '',
      layerTop,
      layerHeight: p.halfD * 2,
    };
  };

  const hitTest = (clientX: number, clientY: number): HitGhost | null => {
    const rect = canvasRef.current?.getBoundingClientRect();
    if (!rect) return null;
    const x = clientX - rect.left;
    const y = clientY - rect.top;
    let best: HitGhost | null = null;
    visible.forEach((ghost) => {
      const projected = projectGhost(ghost, rect.width, rect.height);
      const dist = Math.hypot(projected.x - x, projected.y - y);
      if (dist <= 14 && (!best || dist < best.dist)) {
        best = { ghost, x: projected.x, y: projected.y, dist };
      }
    });
    return best;
  };

  // --- rAF render loop ---
  useEffect(() => {
    let raf = 0;
    const draw = () => {
      const canvas = canvasRef.current;
      const ctx = canvas?.getContext('2d');
      if (canvas && ctx) {
        const rect = canvas.getBoundingClientRect();
        const dpr = window.devicePixelRatio || 1;
        const w = Math.max(1, Math.round(rect.width));
        const h = Math.max(1, Math.round(rect.height));
        if (canvas.width !== w * dpr || canvas.height !== h * dpr) {
          canvas.width = w * dpr;
          canvas.height = h * dpr;
        }
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        ctx.clearRect(0, 0, w, h);

        // Single-scene: keep the camera centred on the active player when
        // follow is on (the world grid then scrolls under the player).
        if (sceneRef.current !== '' && followRef.current) {
          const active = ghostsRef.current.find(g => g.player_id === activeIdRef.current)
            || ghostsRef.current.find(g => g.scene === sceneRef.current);
          if (active) {
            const scale = 2 * camRef.current.zoom;
            camRef.current.offsetX = -active.pos_x * scale;
            camRef.current.offsetY = -active.pos_z * scale;
          }
        }

        const cam = camRef.current;
        const baseScale = 2;
        const scale = baseScale * cam.zoom;
        const cx = w / 2 + cam.offsetX;
        const cy = h / 2 + cam.offsetY;
        const toX = (x: number) => cx + x * scale;
        const toZ = (z: number) => cy + z * scale;

        if (sceneRef.current === '') {
          const layers = sceneLayers();
          layers.forEach((layer, i) => {
            const p = planeGeometry(layer, w, h);
            const contentCam = planeCam(layer);
            const planeZoom = Math.min(2.4, Math.max(0.65, contentCam.zoom)) * globalZoomRef.current;
            const { centerX, centerY, halfW, halfD, corners } = p;
            // Cull planes fully off-screen (stacking can scroll them away).
            if (centerY + halfD < -20 || centerY - halfD > h + 20) return;

            ctx.fillStyle = i % 2 === 0 ? 'rgba(19,22,28,0.82)' : 'rgba(12,14,18,0.82)';
            ctx.strokeStyle = '#2a3140';
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.moveTo(corners[0][0], corners[0][1]);
            corners.slice(1).forEach(([px, py]) => ctx.lineTo(px, py));
            ctx.closePath();
            ctx.fill();
            ctx.stroke();

            ctx.save();
            ctx.beginPath();
            ctx.moveTo(corners[0][0], corners[0][1]);
            corners.slice(1).forEach(([px, py]) => ctx.lineTo(px, py));
            ctx.closePath();
            ctx.clip();
            ctx.strokeStyle = 'rgba(127,209,255,0.12)';
            ctx.lineWidth = 1;

            const gridStep = Math.max(24, 42 * planeZoom);
            const phaseA = ((contentCam.offsetX + contentCam.offsetY) % gridStep + gridStep) % gridStep;
            const phaseB = ((contentCam.offsetX - contentCam.offsetY) % gridStep + gridStep) % gridStep;
            for (let d = -halfW - halfD * 3 - gridStep + phaseA; d < halfW + halfD * 3; d += gridStep) {
              ctx.beginPath();
              ctx.moveTo(centerX + d - halfW, centerY - halfD);
              ctx.lineTo(centerX + d + halfW, centerY + halfD);
              ctx.stroke();
            }
            for (let d = -halfW - halfD * 3 - gridStep + phaseB; d < halfW + halfD * 3; d += gridStep) {
              ctx.beginPath();
              ctx.moveTo(centerX + d + halfW, centerY - halfD);
              ctx.lineTo(centerX + d - halfW, centerY + halfD);
              ctx.stroke();
            }
            ctx.restore();

            ctx.fillStyle = '#7fd1ff';
            ctx.font = 'bold 12px monospace';
            ctx.fillText(layer, corners[3][0] + 8, corners[3][1] - 8);
          });
        }

        // World-space grid (single-scene). Drawn in world coords so it scrolls
        // under the player as the camera follows — a real spatial reference.
        const gridWorld = 10;
        const gridPx = gridWorld * scale;
        if (sceneRef.current !== '' && gridPx > 6) {
          ctx.strokeStyle = '#1c2230';
          ctx.lineWidth = 1;
          const startX = ((cx % gridPx) + gridPx) % gridPx;
          const startY = ((cy % gridPx) + gridPx) % gridPx;
          for (let x = startX; x < w; x += gridPx) {
            ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, h); ctx.stroke();
          }
          for (let y = startY; y < h; y += gridPx) {
            ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke();
          }
          // World origin crosshair, so the grid's reference point is visible.
          ctx.strokeStyle = '#2a3140';
          ctx.setLineDash([4, 4]);
          ctx.beginPath();
          ctx.moveTo(toX(0), 0); ctx.lineTo(toX(0), h);
          ctx.moveTo(0, toZ(0)); ctx.lineTo(w, toZ(0));
          ctx.stroke();
          ctx.setLineDash([]);
        }

        const list = ghostsRef.current.filter(
          g => sceneRef.current === '' || g.scene === sceneRef.current
        );

        list.forEach(g => {
          const trail = trailsRef.current[g.player_id] || [];
          const trailPoints = trail.filter(point => sceneRef.current === '' || point.scene === sceneRef.current);
          if (trailPoints.length < 2) return;
          ctx.strokeStyle = fpsColor(g.fps);
          ctx.lineWidth = 2;
          ctx.globalAlpha = 0.38;
          ctx.beginPath();
          trailPoints.forEach((point, idx) => {
            const projected = projectGhost({ scene: point.scene, pos_x: point.x, pos_z: point.z }, w, h);
            if (idx === 0) ctx.moveTo(projected.x, projected.y);
            else ctx.lineTo(projected.x, projected.y);
          });
          ctx.stroke();
          ctx.globalAlpha = 1;
        });

        list.forEach(g => {
          const projected = projectGhost(g, w, h);
          const sx = projected.x;
          const sz = projected.y;
          const color = fpsColor(g.fps);
          const isActive = g.player_id === activeIdRef.current;
          if (isActive) {
            ctx.strokeStyle = '#7fd1ff';
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.arc(sx, sz, 11, 0, Math.PI * 2);
            ctx.stroke();
          }
          ctx.shadowBlur = 8;
          ctx.shadowColor = color;
          ctx.fillStyle = color;
          ctx.beginPath();
          ctx.arc(sx, sz, isActive ? 7 : 6, 0, Math.PI * 2);
          ctx.fill();
          ctx.shadowBlur = 0;
          ctx.fillStyle = '#d7dbe0';
          ctx.font = '10px monospace';
          ctx.fillText(g.player_id.substring(0, 8), sx + 9, sz + 3);
        });
      }
      raf = requestAnimationFrame(draw);
    };
    raf = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(raf);
  }, []);

  // Zoom clamps per mode.
  const clampGlobal = (z: number) => Math.min(2.6, Math.max(0.5, z));
  const clampPlane = (z: number) => Math.min(2.4, Math.max(0.65, z));
  const clampSingle = (z: number) => Math.min(8, Math.max(0.25, z));

  // --- wheel zoom ---
  // In multi-plane mode: over a plane -> focus that plane; over empty space ->
  // global zoom (scales/spreads all planes). In single-scene -> free zoom.
  const onWheel = useCallback((e: React.WheelEvent) => {
    e.preventDefault();
    const factor = e.deltaY < 0 ? 1.1 : 1 / 1.1;
    if (sceneRef.current === '') {
      const plane = hitPlane(e.clientX, e.clientY);
      if (plane) {
        const cam = planeCam(plane);
        cam.zoom = clampPlane(cam.zoom * factor);
      } else {
        globalZoomRef.current = clampGlobal(globalZoomRef.current * factor);
      }
    } else {
      camRef.current.zoom = clampSingle(camRef.current.zoom * factor);
    }
    forceTick(t => t + 1);
  }, []);

  // --- drag pan + pinch zoom ---
  const drag = useRef<{ x: number; y: number; plane: string | null } | null>(null);
  const dragMoved = useRef(false);
  const pinch = useRef<{ dist: number; zoom: number; mode: 'plane' | 'global' | 'single'; cam?: any } | null>(null);

  const onPointerDown = (e: React.PointerEvent) => {
    (e.target as HTMLElement).setPointerCapture?.(e.pointerId);
    drag.current = { x: e.clientX, y: e.clientY, plane: hitPlane(e.clientX, e.clientY) };
    dragMoved.current = false;
  };
  const onPointerMove = (e: React.PointerEvent) => {
    const hit = hitTest(e.clientX, e.clientY);
    setHover(hit ? { ghost: hit.ghost, x: hit.x, y: hit.y } : null);
    if (!drag.current) return;
    const dx = e.clientX - drag.current.x;
    const dy = e.clientY - drag.current.y;
    if (Math.hypot(dx, dy) > 3) dragMoved.current = true;
    if (sceneRef.current === '') {
      if (drag.current.plane) {
        const cam = planeCam(drag.current.plane);
        cam.offsetX += dx;
        cam.offsetY += dy;
      } else {
        // Empty space -> scroll the whole plane stack vertically.
        stackOffsetRef.current += dy;
      }
    } else {
      // Panning releases follow so the user can look around freely.
      followRef.current = false;
      camRef.current.offsetX += dx;
      camRef.current.offsetY += dy;
    }
    drag.current = { ...drag.current, x: e.clientX, y: e.clientY };
  };
  const onPointerUp = () => {
    if (!dragMoved.current && hover) onSelectGhost?.(hover.ghost.player_id);
    drag.current = null;
  };
  const onPointerLeave = () => {
    setHover(null);
    drag.current = null;
  };

  const touchDist = (t: React.TouchList) =>
    Math.hypot(t[0].clientX - t[1].clientX, t[0].clientY - t[1].clientY);
  const touchMid = (t: React.TouchList) => ({
    x: (t[0].clientX + t[1].clientX) / 2,
    y: (t[0].clientY + t[1].clientY) / 2,
  });

  const onTouchStart = (e: React.TouchEvent) => {
    if (e.touches.length === 2) {
      drag.current = null;
      const mid = touchMid(e.touches);
      if (sceneRef.current === '') {
        const plane = hitPlane(mid.x, mid.y);
        if (plane) {
          const cam = planeCam(plane);
          pinch.current = { dist: touchDist(e.touches), zoom: cam.zoom, mode: 'plane', cam };
        } else {
          pinch.current = { dist: touchDist(e.touches), zoom: globalZoomRef.current, mode: 'global' };
        }
      } else {
        pinch.current = { dist: touchDist(e.touches), zoom: camRef.current.zoom, mode: 'single' };
      }
    }
  };
  const onTouchMove = (e: React.TouchEvent) => {
    if (e.touches.length === 2 && pinch.current) {
      e.preventDefault();
      const ratio = touchDist(e.touches) / pinch.current.dist;
      const target = pinch.current.zoom * ratio;
      if (pinch.current.mode === 'plane') pinch.current.cam.zoom = clampPlane(target);
      else if (pinch.current.mode === 'global') globalZoomRef.current = clampGlobal(target);
      else camRef.current.zoom = clampSingle(target);
      forceTick(t => t + 1);
    }
  };
  const onTouchEnd = (e: React.TouchEvent) => {
    if (e.touches.length < 2) pinch.current = null;
  };

  // +/- buttons: global zoom in multi-plane mode, free zoom in single-scene.
  const zoomBy = (factor: number) => {
    if (sceneRef.current === '') {
      globalZoomRef.current = clampGlobal(globalZoomRef.current * factor);
    } else {
      camRef.current.zoom = clampSingle(camRef.current.zoom * factor);
    }
    forceTick(t => t + 1);
  };

  const resetView = () => {
    camRef.current = { zoom: 1, offsetX: 0, offsetY: 0 };
    planeCamsRef.current = {};
    globalZoomRef.current = 1;
    stackOffsetRef.current = 0;
    followRef.current = true;
    forceTick(t => t + 1);
  };

  const recenterFollow = () => {
    followRef.current = true;
    forceTick(t => t + 1);
  };

  return (
    <div ref={wrapRef} className="w-full h-full relative bg-[#0c0e12] overflow-hidden">
      <canvas
        ref={canvasRef}
        onWheel={onWheel}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerLeave={onPointerLeave}
        onTouchStart={onTouchStart}
        onTouchMove={onTouchMove}
        onTouchEnd={onTouchEnd}
        className="w-full h-full touch-none cursor-grab active:cursor-grabbing"
      />

      <div className="absolute top-3 left-3 pointer-events-none bg-bg-card/90 px-2 py-1 border-2 border-black text-[0.625rem] font-mono">
        LIVE: <span className="text-accent font-bold">{visible.length}</span>
      </div>

      <div className="absolute bottom-3 right-3 flex flex-col gap-2">
        <button
          onClick={() => zoomBy(1.25)}
          className="flex h-10 w-10 items-center justify-center border-2 border-black bg-bg-card/90 hover:bg-accent hover:text-black"
          aria-label="Zoom in"
        >
          <Plus size={18} />
        </button>
        <button
          onClick={() => zoomBy(1 / 1.25)}
          className="flex h-10 w-10 items-center justify-center border-2 border-black bg-bg-card/90 hover:bg-accent hover:text-black"
          aria-label="Zoom out"
        >
          <Minus size={18} />
        </button>
        {sceneName !== '' && (
          <button
            onClick={recenterFollow}
            className={`flex h-10 w-10 items-center justify-center border-2 border-black ${followRef.current ? 'bg-accent text-black' : 'bg-bg-card/90'} hover:bg-accent hover:text-black`}
            aria-label="Follow player"
            title="Seguir al player"
          >
            <LocateFixed size={18} />
          </button>
        )}
        <button
          onClick={resetView}
          className="flex h-10 w-10 items-center justify-center border-2 border-black bg-bg-card/90 hover:bg-accent hover:text-black"
          aria-label="Recenter"
          title="Reset view"
        >
          <Crosshair size={18} />
        </button>
        <button
          onClick={() => setShowHelp((v) => !v)}
          className={`flex h-10 w-10 items-center justify-center border-2 border-black ${showHelp ? 'bg-accent text-black' : 'bg-bg-card/90'} hover:bg-accent hover:text-black`}
          aria-label="Help"
        >
          <HelpCircle size={18} />
        </button>
      </div>

      {showHelp && (
        <div className="absolute bottom-3 left-3 max-w-[60%] border-2 border-black bg-bg-card/95 px-2 py-1.5 text-[0.5625rem] font-mono uppercase leading-relaxed text-text-muted shadow-[2px_2px_0px_0px_black]">
          {sceneName === ''
            ? 'Scroll/pinch sobre plano = enfocar · sobre vacío = zoom global · arrastra = mover · tap player = detalle'
            : 'Scroll/pinch = zoom · arrastra = soltar follow · botón mira = re-seguir · tap player = detalle'}
        </div>
      )}

      {hover && (
        <div
          className="pointer-events-none absolute z-10 border-2 border-black bg-bg-card px-3 py-2 text-[0.625rem] font-mono shadow-[3px_3px_0px_0px_black]"
          style={{ left: Math.min(hover.x + 14, (wrapRef.current?.clientWidth || 0) - 190), top: Math.max(8, hover.y - 18), width: 180 }}
        >
          <div className="font-black text-accent">{hover.ghost.player_id.slice(0, 8)}</div>
          <div className="text-text-muted">{hover.ghost.scene || 'scene —'}</div>
          <div>FPS: <span style={{ color: fpsColor(hover.ghost.fps) }}>{Math.round(hover.ghost.fps || 0)}</span></div>
          <div>Platform: {hover.ghost.platform || '-'}</div>
          <div>Mode: {hover.ghost.mode || '-'}</div>
          <div>Mem: {hover.ghost.memory_mb != null ? `${hover.ghost.memory_mb.toFixed(0)} MB` : '-'}</div>
          <div className="mt-1 text-text-muted">{hover.ghost.pos_x.toFixed(1)}, {hover.ghost.pos_y.toFixed(1)}, {hover.ghost.pos_z.toFixed(1)}</div>
        </div>
      )}
    </div>
  );
};
