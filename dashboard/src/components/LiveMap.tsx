import React, { useEffect, useRef, useState, useCallback } from 'react';

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
}

type HitGhost = { ghost: ActiveGhost; x: number; y: number; dist: number };

const fpsColor = (fps: number) => (fps < 30 ? '#ef4444' : fps < 45 ? '#eab308' : '#22c55e');
const TRAIL_LIMIT = 90;

// Birdseye map with wheel/pinch zoom and drag pan. Renders on a rAF loop so it
// tracks incoming heartbeats in real time. World units -> pixels via `scale`,
// recentred by `offset` (pan).
export const LiveMap: React.FC<LiveMapProps> = ({ ghosts, sceneName, onSelectGhost }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const wrapRef = useRef<HTMLDivElement>(null);

  // Camera: world->screen = center + offset + worldPos * (baseScale * zoom)
  const camRef = useRef({ zoom: 1, offsetX: 0, offsetY: 0 });
  const [, forceTick] = useState(0); // re-render for the live counter
  const [hover, setHover] = useState<{ ghost: ActiveGhost; x: number; y: number } | null>(null);
  const trailsRef = useRef<Record<string, { scene: string; x: number; y: number; z: number }[]>>({});
  const planeCamsRef = useRef<Record<string, { zoom: number; offsetX: number; offsetY: number }>>({});

  // Keep latest props in refs so the rAF loop reads fresh values without
  // re-subscribing.
  const ghostsRef = useRef(ghosts);
  const sceneRef = useRef(sceneName);
  ghostsRef.current = ghosts;
  sceneRef.current = sceneName;

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

  const planeGeometry = (scene: string, width: number, height: number) => {
    const layers = sceneLayers();
    const layerIndex = Math.max(0, layers.indexOf(scene));
    const depth = layerIndex - (layers.length - 1) / 2;
    const centerX = width / 2;
    const centerY = height / 2 + depth * 250;
    const halfW = Math.min(380, Math.max(240, width * 0.34));
    const halfD = 118;
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
    const planeZoom = Math.min(2.2, Math.max(0.65, cam.zoom));
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
      const sx = projected.x;
      const sy = projected.y;
      const dist = Math.hypot(sx - x, sy - y);
      if (dist <= 14 && (!best || dist < best.dist)) {
        best = { ghost, x: sx, y: sy, dist };
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
        // Match the backing store to the displayed size (crisp on HiDPI).
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

        const cam = camRef.current;
        const baseScale = 2; // 1 world unit = 2px at zoom 1
        const scale = baseScale * cam.zoom;
        const cx = w / 2 + cam.offsetX;
        const cy = h / 2 + cam.offsetY;
        const toX = (x: number) => cx + x * scale;
        const toZ = (z: number) => cy + z * scale;

        if (sceneRef.current === '') {
          const layers = sceneLayers();
          layers.forEach((layer, i) => {
            const p = planeGeometry(layer, w, h);
            const planeZoom = Math.min(2.2, Math.max(0.65, planeCam(layer).zoom));
            const contentCam = planeCam(layer);
            const { centerX, centerY, halfW, halfD, corners } = p;
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
            ctx.font = 'bold 11px monospace';
            ctx.fillText(layer, corners[3][0] + 8, corners[3][1] - 8);
          });
        }

        // Grid (in world space, so it pans/zooms with the map). In multi-scene
        // mode each plane has its own grid, so the global grid is hidden.
        const gridWorld = 10; // 10 units between lines
        const gridPx = gridWorld * scale;
        if (sceneRef.current !== '' && gridPx > 6) {
          ctx.strokeStyle = '#1c2230';
          ctx.lineWidth = 1;
          const startX = cx % gridPx;
          const startY = cy % gridPx;
          for (let x = startX; x < w; x += gridPx) {
            ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, h); ctx.stroke();
          }
          for (let y = startY; y < h; y += gridPx) {
            ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke();
          }
        }

        if (sceneRef.current !== '') {
          // Origin crosshair.
          ctx.strokeStyle = '#2a3140';
          ctx.setLineDash([4, 4]);
          ctx.beginPath();
          ctx.moveTo(toX(0), 0); ctx.lineTo(toX(0), h);
          ctx.moveTo(0, toZ(0)); ctx.lineTo(w, toZ(0));
          ctx.stroke();
          ctx.setLineDash([]);
        }

        // Player points.
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
          ctx.shadowBlur = 8;
          ctx.shadowColor = color;
          ctx.fillStyle = color;
          ctx.beginPath();
          ctx.arc(sx, sz, 6, 0, Math.PI * 2);
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

  // --- wheel zoom ---
  const onWheel = useCallback((e: React.WheelEvent) => {
    e.preventDefault();
    const plane = hitPlane(e.clientX, e.clientY);
    const cam = sceneRef.current === '' && plane ? planeCam(plane) : camRef.current;
    const factor = e.deltaY < 0 ? 1.1 : 1 / 1.1;
    cam.zoom = sceneRef.current === ''
      ? Math.min(2.2, Math.max(0.65, cam.zoom * factor))
      : Math.min(8, Math.max(0.25, cam.zoom * factor));
    forceTick(t => t + 1);
  }, []);

  // --- drag pan (mouse + single touch) + pinch zoom (two touches) ---
  const drag = useRef<{ x: number; y: number; plane: string | null } | null>(null);
  const dragMoved = useRef(false);
  const pinch = useRef<{ dist: number; zoom: number } | null>(null);

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
    const cam = sceneRef.current === '' && drag.current.plane ? planeCam(drag.current.plane) : camRef.current;
    cam.offsetX += dx;
    cam.offsetY += dy;
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

  const onTouchStart = (e: React.TouchEvent) => {
    if (e.touches.length === 2) {
      drag.current = null;
      pinch.current = { dist: touchDist(e.touches), zoom: camRef.current.zoom };
    }
  };
  const onTouchMove = (e: React.TouchEvent) => {
    if (e.touches.length === 2 && pinch.current) {
      e.preventDefault();
      const ratio = touchDist(e.touches) / pinch.current.dist;
      camRef.current.zoom = Math.min(8, Math.max(0.25, pinch.current.zoom * ratio));
      forceTick(t => t + 1);
    }
  };
  const onTouchEnd = (e: React.TouchEvent) => {
    if (e.touches.length < 2) pinch.current = null;
  };

  const resetView = () => {
    camRef.current = { zoom: 1, offsetX: 0, offsetY: 0 };
    planeCamsRef.current = {};
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

      <button
        onClick={resetView}
        className="absolute top-3 right-3 bg-bg-card/90 px-2 py-1 border-2 border-black text-[0.625rem] font-mono uppercase font-bold hover:bg-accent hover:text-black"
      >
        Reset
      </button>

      <div className="absolute bottom-3 left-3 pointer-events-none text-[0.5rem] font-mono text-text-muted uppercase">
        Scroll/pinch = zoom · drag = pan · click player = follow 3D
      </div>

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
