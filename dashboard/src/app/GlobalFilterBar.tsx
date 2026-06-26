import type { GeoPlayer } from '../types';
import { useFilters } from '../data/filters.store';
import { useGeoPlayersQuery, useScenesQuery } from '../data/queries';
import { countriesFromGeo } from '../data/selectors';

const SELECT = 'border-2 border-black bg-bg-primary px-2 py-0.5 text-[0.625rem] font-mono text-text-primary';

// Filtros globales: alimentan todas las vistas desde el store central. La escena
// cruza Incidentes + Heatmap; el país, el Globo.
export function GlobalFilterBar() {
  const scene = useFilters((s) => s.scene);
  const country = useFilters((s) => s.country);
  const setFilter = useFilters((s) => s.setFilter);
  const reset = useFilters((s) => s.reset);

  const scenes = useScenesQuery();
  const geo = useGeoPlayersQuery();
  const countries = countriesFromGeo((geo.data as GeoPlayer[]) ?? []);
  const active = !!scene || !!country;

  return (
    <div className="flex flex-wrap items-center gap-2 border-b-2 border-black bg-bg-card/60 px-3 py-1.5">
      <span className="text-[0.5rem] font-black uppercase tracking-widest text-text-muted">Filtros</span>

      <select value={scene} onChange={(e) => setFilter('scene', e.target.value)} className={SELECT} title="Escena">
        <option value="">Todas las escenas</option>
        {(scenes.data ?? []).map((s) => (
          <option key={s} value={s}>
            {s}
          </option>
        ))}
      </select>

      <select value={country} onChange={(e) => setFilter('country', e.target.value)} className={SELECT} title="País">
        <option value="">Todos los países</option>
        {countries.map((c) => (
          <option key={c.code} value={c.code}>
            {c.name} ({c.count})
          </option>
        ))}
      </select>

      {active && (
        <button
          type="button"
          onClick={reset}
          className="border-2 border-black bg-bg-primary px-2 py-0.5 text-[0.5625rem] font-black uppercase text-text-muted hover:bg-danger hover:text-black"
        >
          Limpiar
        </button>
      )}
    </div>
  );
}
