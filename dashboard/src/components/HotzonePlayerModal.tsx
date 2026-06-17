import { useCallback, useEffect, useRef, useState } from 'react';
import { X, ExternalLink, GripVertical, Maximize2, Minimize2 } from 'lucide-react';

// The web shell loads the engine .pck/.wasm from GitHub Pages (see
// odisea_shell.html). Prefetching them while the modal opens means the iframe
// pulls them from cache instead of over the wire — much faster first paint.
const PAGES_BASE = 'https://icarito.github.io/Odisea';
const PREFETCH_ASSETS = [
  `${PAGES_BASE}/index.pck`,
  `${PAGES_BASE}/threads/index.wasm`,
];

// Kick off a background prefetch of the heavy engine assets. Idempotent: a
// given href is only ever injected once per page. Exported so the play button
// can warm the cache on hover, before the modal even opens.
export function prefetchHotzoneEngine() {
  if (typeof document === 'undefined') return;
  for (const href of PREFETCH_ASSETS) {
    if (document.head.querySelector(`link[data-hz-prefetch="${href}"]`)) continue;
    const link = document.createElement('link');
    link.rel = 'prefetch';
    link.as = 'fetch';
    link.crossOrigin = 'anonymous';
    link.href = href;
    link.setAttribute('data-hz-prefetch', href);
    document.head.appendChild(link);
  }
}

const MIN_W = 360;
const MIN_H = 280;
const DEFAULT_W = 880;
const DEFAULT_H = 560;
const MARGIN = 8; // keep the window from being dragged fully off-screen

type Rect = { x: number; y: number; w: number; h: number };

// Center a default-sized window in the viewport, clamped to fit.
function initialRect(): Rect {
  const vw = typeof window === 'undefined' ? 1280 : window.innerWidth;
  const vh = typeof window === 'undefined' ? 800 : window.innerHeight;
  const w = Math.min(DEFAULT_W, vw - MARGIN * 2);
  const h = Math.min(DEFAULT_H, vh - MARGIN * 2);
  return { x: Math.max(MARGIN, (vw - w) / 2), y: Math.max(MARGIN, (vh - h) / 3), w, h };
}

// Floating, draggable and resizable window that plays a hotzone capture inside
// the web shell via an <iframe>. Unlike a modal it has no blocking backdrop, so
// the dashboard stats behind it stay visible and interactive.
export const HotzonePlayerModal = ({
  src,
  onClose,
}: {
  src: string | null;
  onClose: () => void;
}) => {
  const [iframeLoaded, setIframeLoaded] = useState(false);
  const [rect, setRect] = useState<Rect>(initialRect);
  const [maximized, setMaximized] = useState(false);
  // While dragging/resizing we overlay the iframe so it doesn't swallow the
  // pointer events (cross-origin iframes capture the mouse otherwise).
  const [interacting, setInteracting] = useState(false);
  // Stored geometry to restore after un-maximizing.
  const restoreRect = useRef<Rect>(rect);
  // Active pointer gesture; null when idle.
  const gesture = useRef<
    | { type: 'move'; startX: number; startY: number; orig: Rect }
    | { type: 'resize'; startX: number; startY: number; orig: Rect }
    | null
  >(null);

  // Warm the engine asset cache as soon as we have a URL to play.
  useEffect(() => {
    if (src) prefetchHotzoneEngine();
  }, [src]);

  // Reset the loading veil and recenter the window on each new capture.
  useEffect(() => {
    if (!src) return;
    setIframeLoaded(false);
    setMaximized(false);
    setRect(initialRect());
  }, [src]);

  // Esc closes the window.
  useEffect(() => {
    if (!src) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [src, onClose]);

  // Global pointer handlers for an in-flight drag/resize gesture.
  useEffect(() => {
    if (!interacting) return;
    const onMove = (e: PointerEvent) => {
      const g = gesture.current;
      if (!g) return;
      const dx = e.clientX - g.startX;
      const dy = e.clientY - g.startY;
      const vw = window.innerWidth;
      const vh = window.innerHeight;
      if (g.type === 'move') {
        const x = Math.min(Math.max(MARGIN - g.orig.w + 80, g.orig.x + dx), vw - 80);
        const y = Math.min(Math.max(MARGIN, g.orig.y + dy), vh - 40);
        setRect((r) => ({ ...r, x, y }));
      } else {
        const w = Math.min(Math.max(MIN_W, g.orig.w + dx), vw - g.orig.x - MARGIN);
        const h = Math.min(Math.max(MIN_H, g.orig.h + dy), vh - g.orig.y - MARGIN);
        setRect((r) => ({ ...r, w, h }));
      }
    };
    const onUp = () => {
      gesture.current = null;
      setInteracting(false);
    };
    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
    return () => {
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerup', onUp);
    };
  }, [interacting]);

  const startDrag = useCallback(
    (e: React.PointerEvent) => {
      if (maximized) return;
      e.preventDefault();
      gesture.current = { type: 'move', startX: e.clientX, startY: e.clientY, orig: rect };
      setInteracting(true);
    },
    [maximized, rect],
  );

  const startResize = useCallback(
    (e: React.PointerEvent) => {
      if (maximized) return;
      e.preventDefault();
      e.stopPropagation();
      gesture.current = { type: 'resize', startX: e.clientX, startY: e.clientY, orig: rect };
      setInteracting(true);
    },
    [maximized, rect],
  );

  const toggleMaximize = useCallback(() => {
    setMaximized((m) => {
      if (!m) restoreRect.current = rect;
      else setRect(restoreRect.current);
      return !m;
    });
  }, [rect]);

  if (!src) return null;

  const style: React.CSSProperties = maximized
    ? { left: MARGIN, top: MARGIN, right: MARGIN, bottom: MARGIN }
    : { left: rect.x, top: rect.y, width: rect.w, height: rect.h };

  return (
    <div
      className="fixed z-[9998] flex flex-col overflow-hidden border-4 border-black bg-bg-card shadow-[6px_6px_0px_0px_black] animate-in zoom-in-95 fade-in duration-200"
      style={style}
      role="dialog"
      aria-label="Reproductor de hotzone"
    >
      {/* Header strip — drag handle */}
      <div
        className={`flex shrink-0 items-center justify-between border-b-4 border-black bg-black px-3 py-2 ${
          maximized ? '' : 'cursor-grab active:cursor-grabbing'
        }`}
        onPointerDown={startDrag}
        onDoubleClick={toggleMaximize}
      >
        <span className="flex items-center gap-1.5 font-mono text-[0.625rem] font-black uppercase tracking-widest text-accent">
          <GripVertical size={12} className="text-text-muted" />
          Reproductor de hotzone
        </span>
        <div className="flex items-center gap-2" onPointerDown={(e) => e.stopPropagation()}>
          <a
            href={src}
            target="_blank"
            rel="noopener noreferrer"
            className="border-2 border-accent bg-accent/10 p-1 text-accent hover:bg-accent hover:text-black"
            title="Abrir en pestaña nueva"
          >
            <ExternalLink size={14} />
          </a>
          <button
            type="button"
            onClick={toggleMaximize}
            className="border-2 border-accent bg-accent/10 p-1 text-accent hover:bg-accent hover:text-black"
            title={maximized ? 'Restaurar' : 'Maximizar'}
            aria-label={maximized ? 'Restaurar ventana' : 'Maximizar ventana'}
          >
            {maximized ? <Minimize2 size={14} /> : <Maximize2 size={14} />}
          </button>
          <button
            type="button"
            onClick={onClose}
            className="border-2 border-danger bg-danger/10 p-1 text-danger hover:bg-danger hover:text-white"
            title="Cerrar (Esc)"
            aria-label="Cerrar reproductor"
          >
            <X size={14} />
          </button>
        </div>
      </div>

      {/* Player surface */}
      <div className="relative min-h-0 flex-1 bg-black">
        <iframe
          src={src}
          title="Hotzone replay"
          className="h-full w-full border-0"
          allow="autoplay; fullscreen; gamepad"
          onLoad={() => setIframeLoaded(true)}
        />

        {/* Transparent shield: while dragging/resizing it sits above the iframe
            so the cross-origin frame doesn't capture the pointer mid-gesture. */}
        {interacting && <div className="absolute inset-0 z-10 cursor-grabbing" />}

        {/* Loading veil: covers the iframe until it reports loaded. The shell
            still streams the engine after that, but this hides the blank
            frame and the abrupt swap. */}
        {!iframeLoaded && (
          <div className="absolute inset-0 flex flex-col items-center justify-center gap-4 bg-bg-primary animate-in fade-in duration-200">
            <span className="h-10 w-10 animate-spin rounded-full border-4 border-text-muted border-t-accent" />
            <span className="font-mono text-xs font-black uppercase tracking-widest text-text-muted">
              Cargando reproductor…
            </span>
          </div>
        )}
      </div>

      {/* Resize grip — bottom-right corner */}
      {!maximized && (
        <div
          onPointerDown={startResize}
          className="absolute bottom-0 right-0 z-20 h-5 w-5 cursor-nwse-resize"
          title="Redimensionar"
          aria-hidden="true"
        >
          <div className="absolute bottom-1 right-1 h-0 w-0 border-b-[10px] border-l-[10px] border-b-accent border-l-transparent" />
        </div>
      )}
    </div>
  );
};
