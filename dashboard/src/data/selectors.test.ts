import { afterEach, describe, expect, it, vi } from 'vitest';
import type { GeoPlayer, IncidentGroup } from '../types';
import { DEFAULT_FILTERS, type GlobalFilters } from './filters.store';
import {
  applyIncidentStatusToList,
  countriesFromGeo,
  filterGeoPlayers,
  filterIncidents,
} from './selectors';

// Factories — solo los campos que los selectores miran; el resto, valores válidos
// pero irrelevantes, para no acoplar los tests a la forma completa del tipo.
function incident(overrides: Partial<IncidentGroup>): IncidentGroup {
  return {
    id: 'i1',
    type: 'low_fps',
    scene: 'OdiseaExterior',
    zone: 'z1',
    spatial_cluster_x: 0,
    spatial_cluster_z: 0,
    status: 'open',
    count: 1,
    first_seen: 0,
    last_seen: 0,
    builds_seen: [],
    ...overrides,
  };
}

function geo(overrides: Partial<GeoPlayer>): GeoPlayer {
  return {
    player_id: 'p1',
    session_id: 's1',
    last_seen: 0,
    country: 'Peru',
    country_code: 'PE',
    city: 'Lima',
    latitude: 0,
    longitude: 0,
    status: 'connected',
    ...overrides,
  };
}

function filters(overrides: Partial<GlobalFilters>): GlobalFilters {
  return { ...DEFAULT_FILTERS, ...overrides };
}

describe('filterIncidents', () => {
  const items = [
    incident({ id: 'a', scene: 'OdiseaExterior' }),
    incident({ id: 'b', scene: 'OdiseaInterior' }),
    incident({ id: 'c', scene: 'OdiseaExterior' }),
  ];

  it('returns every item when no scene is set', () => {
    expect(filterIncidents(items, filters({ scene: '' }))).toEqual(items);
  });

  it('returns the same array reference (no copy) when unfiltered', () => {
    // Barato y predecible: las vistas pueden comparar por identidad.
    expect(filterIncidents(items, DEFAULT_FILTERS)).toBe(items);
  });

  it('keeps only incidents matching the selected scene', () => {
    const out = filterIncidents(items, filters({ scene: 'OdiseaExterior' }));
    expect(out.map((i) => i.id)).toEqual(['a', 'c']);
  });

  it('returns empty when no incident matches the scene', () => {
    expect(filterIncidents(items, filters({ scene: 'Nowhere' }))).toEqual([]);
  });

  it('does not mutate the input', () => {
    const copy = [...items];
    filterIncidents(items, filters({ scene: 'OdiseaInterior' }));
    expect(items).toEqual(copy);
  });
});

describe('filterGeoPlayers', () => {
  it('returns every player when no filters are set', () => {
    const items = [geo({ player_id: 'a' }), geo({ player_id: 'b' })];
    expect(filterGeoPlayers(items, DEFAULT_FILTERS)).toBe(items);
  });

  it('filters by country code case-insensitively', () => {
    const items = [
      geo({ player_id: 'a', country_code: 'PE' }),
      geo({ player_id: 'b', country_code: 'us' }),
      geo({ player_id: 'c', country_code: 'PE' }),
    ];
    const out = filterGeoPlayers(items, filters({ country: 'pe' }));
    expect(out.map((p) => p.player_id)).toEqual(['a', 'c']);
  });

  it('treats missing country_code as non-matching', () => {
    const items = [
      geo({ player_id: 'a', country_code: '' }),
      geo({ player_id: 'b', country_code: 'PE' }),
    ];
    const out = filterGeoPlayers(items, filters({ country: 'PE' }));
    expect(out.map((p) => p.player_id)).toEqual(['b']);
  });

  describe('windowMs (recency)', () => {
    const NOW_MS = 1_700_000_000_000;
    afterEach(() => vi.useRealTimers());

    it('keeps only players seen within the window', () => {
      vi.useFakeTimers();
      vi.setSystemTime(NOW_MS);
      const nowSec = NOW_MS / 1000;
      const items = [
        geo({ player_id: 'fresh', last_seen: nowSec - 10 }), // 10s ago
        geo({ player_id: 'stale', last_seen: nowSec - 120 }), // 2min ago
      ];
      const out = filterGeoPlayers(items, filters({ windowMs: 60_000 })); // 60s
      expect(out.map((p) => p.player_id)).toEqual(['fresh']);
    });

    it('treats missing last_seen as oldest (filtered out)', () => {
      vi.useFakeTimers();
      vi.setSystemTime(NOW_MS);
      const items = [geo({ player_id: 'unknown', last_seen: undefined as unknown as number })];
      expect(filterGeoPlayers(items, filters({ windowMs: 60_000 }))).toEqual([]);
    });
  });

  it('applies country and window filters together', () => {
    const NOW_MS = 1_700_000_000_000;
    vi.useFakeTimers();
    vi.setSystemTime(NOW_MS);
    const nowSec = NOW_MS / 1000;
    const items = [
      geo({ player_id: 'a', country_code: 'PE', last_seen: nowSec - 5 }),
      geo({ player_id: 'b', country_code: 'PE', last_seen: nowSec - 999 }),
      geo({ player_id: 'c', country_code: 'US', last_seen: nowSec - 5 }),
    ];
    const out = filterGeoPlayers(items, filters({ country: 'PE', windowMs: 60_000 }));
    expect(out.map((p) => p.player_id)).toEqual(['a']);
    vi.useRealTimers();
  });
});

describe('countriesFromGeo', () => {
  it('counts players per country code, sorted by count desc', () => {
    const items = [
      geo({ country_code: 'PE', country: 'Peru' }),
      geo({ country_code: 'US', country: 'United States' }),
      geo({ country_code: 'PE', country: 'Peru' }),
      geo({ country_code: 'PE', country: 'Peru' }),
      geo({ country_code: 'US', country: 'United States' }),
    ];
    expect(countriesFromGeo(items)).toEqual([
      { code: 'PE', name: 'Peru', count: 3 },
      { code: 'US', name: 'United States', count: 2 },
    ]);
  });

  it('normalizes codes to upper-case and merges casing variants', () => {
    const items = [geo({ country_code: 'pe' }), geo({ country_code: 'PE' })];
    const out = countriesFromGeo(items);
    expect(out).toHaveLength(1);
    expect(out[0]).toMatchObject({ code: 'PE', count: 2 });
  });

  it('skips players without a country code', () => {
    const items = [geo({ country_code: '' }), geo({ country_code: 'PE' })];
    expect(countriesFromGeo(items).map((c) => c.code)).toEqual(['PE']);
  });

  it('falls back to the code as name when country is empty', () => {
    const items = [geo({ country_code: 'XX', country: '' })];
    expect(countriesFromGeo(items)[0]).toMatchObject({ code: 'XX', name: 'XX' });
  });

  it('returns an empty list for empty input', () => {
    expect(countriesFromGeo([])).toEqual([]);
  });
});

describe('applyIncidentStatusToList (optimistic mutation core)', () => {
  it('updates the target incident status in an unfiltered list', () => {
    const list = [incident({ id: 'a', status: 'open' }), incident({ id: 'b', status: 'open' })];
    const out = applyIncidentStatusToList(list, 'a', 'resolved', 'all');
    expect(out.map((i) => [i.id, i.status])).toEqual([
      ['a', 'resolved'],
      ['b', 'open'],
    ]);
  });

  it('drops the incident from a list filtered by a now-mismatching status', () => {
    // Lista de "open": al marcar 'a' como resolved, debe desaparecer de esta query.
    const list = [incident({ id: 'a', status: 'open' }), incident({ id: 'b', status: 'open' })];
    const out = applyIncidentStatusToList(list, 'a', 'resolved', 'open');
    expect(out.map((i) => i.id)).toEqual(['b']);
  });

  it('keeps the incident when the new status still matches the filter', () => {
    const list = [incident({ id: 'a', status: 'open' })];
    const out = applyIncidentStatusToList(list, 'a', 'open', 'open');
    expect(out.map((i) => [i.id, i.status])).toEqual([['a', 'open']]);
  });

  it('leaves the list unchanged when the id is absent', () => {
    const list = [incident({ id: 'a', status: 'open' })];
    const out = applyIncidentStatusToList(list, 'zzz', 'resolved', 'all');
    expect(out.map((i) => [i.id, i.status])).toEqual([['a', 'open']]);
  });

  it('does not mutate the input array or its items', () => {
    const list = [incident({ id: 'a', status: 'open' })];
    const snapshot = JSON.parse(JSON.stringify(list));
    applyIncidentStatusToList(list, 'a', 'resolved', 'all');
    expect(list).toEqual(snapshot);
  });
});
