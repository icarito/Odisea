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
}

interface LiveMapProps {
  ghosts: ActiveGhost[];
  sceneName: string;
}

const fpsColor = (fps: number) => (fps < 30 ? '#ef4444' : fps < 45 ? '#eab308' : '#22c55e');

// Birdseye map with wheel/pinch zoom and drag pan. Renders on a rAF loop so it
// tracks incoming heartbeats in real time. World units -> pixels via `scale`,
// recentred by `offset` (pan).
export const LiveMap: React.FC<LiveMapProps> = ({ ghosts, sceneName }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const wrapRef = useRef<HTMLDivElement>(null);

  // Camera: world->screen = center + offset + worldPos * (baseScale * zoom)
  const camRef = useRef({ zoom: 1, offsetX: 0, offsetY: 0 });
  const [, forceTick] = useState(0); // re-render for the live counter

  // Keep latest props in refs so the rAF loop reads fresh values without
  // re-subscribing.
  const ghostsRef = useRef(ghosts);
  const sceneRef = useRef(sceneName);
  ghostsRef.current = ghosts;
  sceneRef.current = sceneName;

  const visible = ghosts.filter(g => sceneName === '' || g.scene === sceneName);

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

        // Grid (in world space, so it pans/zooms with the map).
        const gridWorld = 10; // 10 units between lines
        const gridPx = gridWorld * scale;
        if (gridPx > 6) {
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

        // Origin crosshair.
        ctx.strokeStyle = '#2a3140';
        ctx.setLineDash([4, 4]);
        ctx.beginPath();
        ctx.moveTo(toX(0), 0); ctx.lineTo(toX(0), h);
        ctx.moveTo(0, toZ(0)); ctx.lineTo(w, toZ(0));
        ctx.stroke();
        ctx.setLineDash([]);

        // Player points.
        const list = ghostsRef.current.filter(
          g => sceneRef.current === '' || g.scene === sceneRef.current
        );
        list.forEach(g => {
          const sx = toX(g.pos_x);
          const sz = toZ(g.pos_z);
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
    const cam = camRef.current;
    const factor = e.deltaY < 0 ? 1.1 : 1 / 1.1;
    cam.zoom = Math.min(8, Math.max(0.25, cam.zoom * factor));
    forceTick(t => t + 1);
  }, []);

  // --- drag pan (mouse + single touch) + pinch zoom (two touches) ---
  const drag = useRef<{ x: number; y: number } | null>(null);
  const pinch = useRef<{ dist: number; zoom: number } | null>(null);

  const onPointerDown = (e: React.PointerEvent) => {
    (e.target as HTMLElement).setPointerCapture?.(e.pointerId);
    drag.current = { x: e.clientX, y: e.clientY };
  };
  const onPointerMove = (e: React.PointerEvent) => {
    if (!drag.current) return;
    const cam = camRef.current;
    cam.offsetX += e.clientX - drag.current.x;
    cam.offsetY += e.clientY - drag.current.y;
    drag.current = { x: e.clientX, y: e.clientY };
  };
  const onPointerUp = () => { drag.current = null; };

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
        onPointerLeave={onPointerUp}
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
        Scroll/pinch = zoom · drag = pan
      </div>
    </div>
  );
};
