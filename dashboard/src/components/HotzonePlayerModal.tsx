import { useEffect, useRef, useState } from 'react';
import { X, ExternalLink } from 'lucide-react';

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

// Fullscreen modal that plays a hotzone capture inside the web shell via an
// <iframe>, with a zoom-in entrance and a loading veil until the engine boots.
export const HotzonePlayerModal = ({
  src,
  onClose,
}: {
  src: string | null;
  onClose: () => void;
}) => {
  const [iframeLoaded, setIframeLoaded] = useState(false);
  const iframeRef = useRef<HTMLIFrameElement | null>(null);

  // Warm the engine asset cache as soon as we have a URL to play.
  useEffect(() => {
    if (src) prefetchHotzoneEngine();
  }, [src]);

  // Reset the loading veil whenever a new capture is opened.
  useEffect(() => {
    setIframeLoaded(false);
  }, [src]);

  // Esc closes the modal.
  useEffect(() => {
    if (!src) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [src, onClose]);

  if (!src) return null;

  return (
    <div
      className="fixed inset-0 z-[9998] flex items-center justify-center bg-black/80 p-2 backdrop-blur-sm animate-in fade-in duration-200 sm:p-6"
      onClick={onClose}
      role="dialog"
      aria-modal="true"
      aria-label="Reproductor de hotzone"
    >
      <div
        className="relative flex h-full w-full flex-col overflow-hidden border-4 border-black bg-bg-card shadow-[6px_6px_0px_0px_black] animate-in zoom-in-95 fade-in duration-300 sm:h-[90vh] sm:w-[90vw]"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header strip */}
        <div className="flex shrink-0 items-center justify-between border-b-4 border-black bg-black px-3 py-2">
          <span className="font-mono text-[0.625rem] font-black uppercase tracking-widest text-accent">
            Reproductor de hotzone
          </span>
          <div className="flex items-center gap-2">
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
            ref={iframeRef}
            src={src}
            title="Hotzone replay"
            className="h-full w-full border-0"
            allow="autoplay; fullscreen; gamepad"
            onLoad={() => setIframeLoaded(true)}
          />

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
      </div>
    </div>
  );
};
