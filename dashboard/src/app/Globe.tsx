import { Suspense, lazy } from 'react';
import { useFilteredGeoPlayers } from '../data/queries';

const GlobeView = lazy(() => import('../components/GlobeView').then((m) => ({ default: m.GlobeView })));

export function Globe() {
  // Geo desde el pipeline central, ya filtrado por el filtro global de país.
  // react-query maneja el refetch en vivo (15s) y la cache.
  const { data, isFetching } = useFilteredGeoPlayers();
  const players = data ?? [];

  return (
    <div className="flex h-full flex-col p-3">
      <div className="mb-2 flex items-center gap-2">
        <span className="text-[0.625rem] font-black uppercase tracking-widest text-accent">Globe</span>
        {isFetching && <span className="text-[0.5625rem] uppercase text-text-muted">actualizando…</span>}
        <span className="ml-auto text-[0.5625rem] uppercase text-text-muted">{players.length} ubicaciones</span>
      </div>
      <div className="min-h-0 flex-1 border-2 border-black bg-bg-card">
        <Suspense
          fallback={
            <div className="flex h-full items-center justify-center text-[0.625rem] font-black uppercase tracking-widest text-text-muted">
              Cargando mapa…
            </div>
          }
        >
          <GlobeView players={players} />
        </Suspense>
      </div>
    </div>
  );
}
