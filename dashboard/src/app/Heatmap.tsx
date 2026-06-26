import { Suspense, lazy, useState } from 'react';
import { useFilters } from '../data/filters.store';
import { useHeatmapQuery, useScenesQuery } from '../data/queries';

// El componente 3D pesado (three/fiber/drei) se carga lazy.
const Heatmap3D = lazy(() => import('../components/Heatmap3D').then((m) => ({ default: m.Heatmap3D })));

const RESOLUTIONS = [3, 5, 8];

export function Heatmap() {
  const globalScene = useFilters((s) => s.scene);
  const scenes = useScenesQuery();
  const [resolution, setResolution] = useState(5);

  // El heatmap es por-escena: usa la escena del filtro global; si es "todas",
  // cae a la primera escena disponible (sin escribir el filtro global).
  const effectiveScene = globalScene || scenes.data?.[0] || '';
  const heatmap = useHeatmapQuery(effectiveScene, resolution);
  const data = (heatmap.data as any[]) ?? [];

  return (
    <div className="flex h-full flex-col gap-2 p-3">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-[0.625rem] font-black uppercase tracking-widest text-accent">Heatmap</span>
        <span className="font-mono text-[0.625rem] text-text-primary">{effectiveScene || '(sin escena)'}</span>
        {!globalScene && effectiveScene && (
          <span className="text-[0.5rem] uppercase tracking-wide text-text-muted">por defecto · filtrá escena arriba</span>
        )}
        <div className="flex items-center gap-1">
          {RESOLUTIONS.map((r) => (
            <button
              key={r}
              type="button"
              onClick={() => setResolution(r)}
              className={`border-2 border-black px-2 py-0.5 text-[0.5625rem] font-black uppercase ${
                resolution === r ? 'bg-accent text-black' : 'bg-bg-primary text-text-muted hover:text-accent'
              }`}
            >
              {r}
            </button>
          ))}
        </div>
        {heatmap.isFetching && <span className="text-[0.5625rem] uppercase text-text-muted">cargando…</span>}
        <span className="ml-auto text-[0.5625rem] uppercase text-text-muted">{data.length} celdas</span>
      </div>
      <div className="min-h-0 flex-1 border-2 border-black bg-bg-card">
        <Suspense
          fallback={
            <div className="flex h-full items-center justify-center text-[0.625rem] font-black uppercase tracking-widest text-text-muted">
              Cargando heatmap…
            </div>
          }
        >
          <Heatmap3D data={data} resolution={resolution} scene={effectiveScene} />
        </Suspense>
      </div>
    </div>
  );
}
