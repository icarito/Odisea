import { Suspense, lazy, useMemo, useState } from 'react';
import { useFilters } from '../data/filters.store';
import { useGhostsQuery, useHeatmapQuery, useScenesQuery } from '../data/queries';
import type { GhostPoint } from '../components/Heatmap3D';

// El componente 3D pesado (three/fiber/drei) se carga lazy.
const Heatmap3D = lazy(() => import('../components/Heatmap3D').then((m) => ({ default: m.Heatmap3D })));

const RESOLUTIONS = [3, 5, 8];
const MAX_GHOSTS = 20000; // tope para que la nube de puntos no penalice el render

function toGhostPoints(raw: unknown): GhostPoint[] {
  if (!Array.isArray(raw)) return [];
  const out: GhostPoint[] = [];
  for (const r of raw as Array<Record<string, unknown>>) {
    const pos = (r.pos as number[]) || [];
    const x = (r.pos_x as number) ?? pos[0] ?? 0;
    const y = (r.pos_y as number) ?? pos[1] ?? 0;
    const z = (r.pos_z as number) ?? pos[2] ?? 0;
    if (!x && !y && !z) continue;
    const fps = (r.fps as number) ?? (r.heartbeat_fps as number) ?? 0;
    out.push({ x, y, z, fps });
    if (out.length >= MAX_GHOSTS) break;
  }
  return out;
}

export function Heatmap() {
  const globalScene = useFilters((s) => s.scene);
  const scenes = useScenesQuery();
  const [resolution, setResolution] = useState(5);
  const [show3D, setShow3D] = useState(true);

  // El heatmap es por-escena: usa la escena del filtro global; si es "todas",
  // cae a la primera escena disponible (sin escribir el filtro global).
  const effectiveScene = globalScene || scenes.data?.[0] || '';
  const heatmap = useHeatmapQuery(effectiveScene, resolution);
  const ghostsQ = useGhostsQuery(show3D ? effectiveScene : '');

  const cells = (heatmap.data as any[]) ?? [];
  const ghosts = useMemo(() => (show3D ? toGhostPoints(ghostsQ.data) : []), [show3D, ghostsQ.data]);

  return (
    <div className="flex h-full flex-col gap-2 p-3">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-[0.625rem] font-black uppercase tracking-widest text-accent">Heatmap</span>
        <span className="font-mono text-[0.625rem] text-text-primary">{effectiveScene || '(sin escena)'}</span>
        {!globalScene && effectiveScene && (
          <span className="text-[0.5rem] uppercase tracking-wide text-text-muted">por defecto · filtrá escena arriba</span>
        )}
        <button
          type="button"
          onClick={() => setShow3D((v) => !v)}
          className={`border-2 border-black px-2 py-0.5 text-[0.5625rem] font-black uppercase ${
            show3D ? 'bg-accent text-black' : 'bg-bg-primary text-text-muted hover:text-accent'
          }`}
          title="Nube de jugadores 3D coloreada por FPS"
        >
          Puntos 3D
        </button>
        <div className="flex items-center gap-1">
          {RESOLUTIONS.map((r) => (
            <button
              key={r}
              type="button"
              onClick={() => setResolution(r)}
              className={`border-2 border-black px-2 py-0.5 text-[0.5625rem] font-black uppercase ${
                resolution === r ? 'bg-accent text-black' : 'bg-bg-primary text-text-muted hover:text-accent'
              }`}
              title="Resolución de la grilla de severidad"
            >
              {r}
            </button>
          ))}
        </div>
        {(heatmap.isFetching || (show3D && ghostsQ.isFetching)) && (
          <span className="text-[0.5625rem] uppercase text-text-muted">cargando…</span>
        )}
        <span className="ml-auto text-[0.5625rem] uppercase text-text-muted">
          {cells.length} celdas{show3D ? ` · ${ghosts.length} puntos` : ''}
        </span>
      </div>
      <div className="min-h-0 flex-1 border-2 border-black bg-bg-card">
        <Suspense
          fallback={
            <div className="flex h-full items-center justify-center text-[0.625rem] font-black uppercase tracking-widest text-text-muted">
              Cargando heatmap…
            </div>
          }
        >
          <Heatmap3D data={cells} resolution={resolution} scene={effectiveScene} ghosts={ghosts} />
        </Suspense>
      </div>
    </div>
  );
}
