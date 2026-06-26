import { Suspense, lazy, useEffect, useState } from 'react';
import { getGeoPlayers } from '../api';

const GlobeView = lazy(() => import('../components/GlobeView').then((m) => ({ default: m.GlobeView })));

export function Globe() {
  const [players, setPlayers] = useState<any[]>([]);

  useEffect(() => {
    let cancelled = false;
    const load = () =>
      getGeoPlayers()
        .then((d) => {
          if (!cancelled) setPlayers(Array.isArray(d) ? d : []);
        })
        .catch(() => {});
    load();
    const id = setInterval(load, 15000); // refresco suave de ubicaciones en vivo
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, []);

  return (
    <div className="flex h-full flex-col p-3">
      <div className="mb-2 flex items-center gap-2">
        <span className="text-[0.625rem] font-black uppercase tracking-widest text-accent">Globe</span>
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
