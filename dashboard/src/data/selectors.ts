import type { GeoPlayer, IncidentGroup } from '../types';
import type { GlobalFilters } from './filters.store';

// Selectores PUROS (sin React) — cruzan dataset + filtros globales. Viven acá
// para poder testearlos en aislamiento, sin montar componentes ni red.

export function filterIncidents(items: IncidentGroup[], f: GlobalFilters): IncidentGroup[] {
  if (!f.scene) return items;
  return items.filter((i) => i.scene === f.scene);
}

export function filterGeoPlayers(items: GeoPlayer[], f: GlobalFilters): GeoPlayer[] {
  let out = items;
  if (f.country) {
    const c = f.country.toUpperCase();
    out = out.filter((p) => (p.country_code || '').toUpperCase() === c);
  }
  if (f.windowMs > 0) {
    const cutoff = Date.now() / 1000 - f.windowMs / 1000;
    out = out.filter((p) => (p.last_seen || 0) >= cutoff);
  }
  return out;
}

// Lista de países presente en los datos de geo (para poblar el filtro de país),
// ordenada por cantidad desc.
export function countriesFromGeo(items: GeoPlayer[]): Array<{ code: string; name: string; count: number }> {
  const by = new Map<string, { code: string; name: string; count: number }>();
  for (const p of items) {
    const code = (p.country_code || '').toUpperCase();
    if (!code) continue;
    const cur = by.get(code) || { code, name: p.country || code, count: 0 };
    cur.count += 1;
    by.set(code, cur);
  }
  return [...by.values()].sort((a, b) => b.count - a.count);
}
