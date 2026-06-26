import { Suspense, lazy, useMemo, useState } from 'react';
import { HistoricalTable } from '../components/HistoricalTable';
import { useFilters } from '../data/filters.store';
import { useFilteredHistoricalSessions, useGhostDataQuery, useHistoricalSessionsQuery } from '../data/queries';
import { platformsFromSessions } from '../data/selectors';

// SessionPlayback arrastra Viewport3D (three/fiber) — carga lazy como en el clásico.
const SessionPlayback = lazy(() =>
  import('../components/SessionPlayback').then((m) => ({ default: m.SessionPlayback })),
);

const DURATIONS = [
  { label: 'Todo', sec: 0 },
  { label: '13s+', sec: 13 },
  { label: '1m+', sec: 60 },
  { label: '5m+', sec: 300 },
];

// Vista History (sesiones) portada a la shell incident-first. Presentacional:
// toda la data viene del pipeline (sesiones + geo, filtradas por los filtros
// globales). Suma los filtros de plataforma y duración mínima (Fase 3 #4), que
// sólo aplican acá y escriben en el mismo store global.
export function History() {
  const platform = useFilters((s) => s.platform);
  const minDurationSec = useFilters((s) => s.minDurationSec);
  const setFilter = useFilters((s) => s.setFilter);

  const sessionsQ = useFilteredHistoricalSessions();
  const rawQ = useHistoricalSessionsQuery();
  const sessions = (sessionsQ.data as Array<Record<string, unknown>>) ?? [];

  // Opciones de plataforma desde el set crudo (no el filtrado), para no
  // esconder plataformas al filtrar por una.
  const platforms = useMemo(
    () => platformsFromSessions((rawQ.data as Array<Record<string, unknown>>) ?? []),
    [rawQ.data],
  );

  const [selected, setSelected] = useState<Record<string, unknown> | null>(null);
  const playerId = selected?.player_id as string | undefined;
  const sessionId = selected?.session_id as string | undefined;
  const playbackQ = useGhostDataQuery(playerId, sessionId);
  const playback = playbackQ.data ?? [];

  return (
    <div className="flex h-full flex-col gap-2 p-3">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-[0.625rem] font-black uppercase tracking-widest text-accent">Sesiones</span>

        <select
          value={platform}
          onChange={(e) => setFilter('platform', e.target.value)}
          className="border-2 border-black bg-bg-primary px-2 py-0.5 text-[0.625rem] font-mono text-text-primary"
          title="Plataforma"
        >
          <option value="">Todas las plataformas</option>
          {platforms.map((p) => (
            <option key={p.platform} value={p.platform}>
              {p.platform} ({p.count})
            </option>
          ))}
        </select>

        <div className="flex items-center gap-1">
          {DURATIONS.map((d) => (
            <button
              key={d.sec}
              type="button"
              onClick={() => setFilter('minDurationSec', d.sec)}
              className={`border-2 border-black px-2 py-0.5 text-[0.5625rem] font-black uppercase ${
                minDurationSec === d.sec ? 'bg-accent text-black' : 'bg-bg-primary text-text-muted hover:text-accent'
              }`}
              title="Duración mínima de sesión"
            >
              {d.label}
            </button>
          ))}
        </div>

        {sessionsQ.isFetching && <span className="text-[0.5625rem] uppercase text-text-muted">cargando…</span>}
        <span className="ml-auto text-[0.5625rem] uppercase text-text-muted">{sessions.length} sesiones</span>
      </div>

      <div className="grid min-h-0 flex-1 grid-cols-1 gap-2 overflow-hidden xl:grid-cols-[360px_minmax(0,1fr)]">
        <div className="min-h-0 overflow-y-auto border-2 border-black bg-bg-card">
          {sessions.length === 0 ? (
            <div className="flex h-full items-center justify-center p-4 text-center text-[0.625rem] uppercase tracking-widest text-text-muted">
              {sessionsQ.isLoading ? 'Cargando sesiones…' : 'Sin sesiones para los filtros actuales'}
            </div>
          ) : (
            <HistoricalTable
              sessions={sessions}
              onSelectSession={setSelected}
              selectedSessionId={sessionId}
            />
          )}
        </div>

        <div className="min-h-0 overflow-hidden border-2 border-black bg-bg-card">
          {!selected ? (
            <div className="flex h-full items-center justify-center p-4 text-center text-[0.625rem] uppercase tracking-widest text-text-muted">
              Elegí una sesión para reproducirla
            </div>
          ) : playbackQ.isLoading ? (
            <div className="flex h-full items-center justify-center text-[0.625rem] font-black uppercase tracking-widest text-text-muted">
              Cargando reproducción…
            </div>
          ) : (
            <Suspense
              fallback={
                <div className="flex h-full items-center justify-center text-[0.625rem] font-black uppercase tracking-widest text-text-muted">
                  Cargando 3D…
                </div>
              }
            >
              <SessionPlayback heartbeats={playback} session={selected} />
            </Suspense>
          )}
        </div>
      </div>
    </div>
  );
}
