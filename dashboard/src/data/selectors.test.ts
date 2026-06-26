import { afterEach, describe, expect, it, vi } from 'vitest';
import type { GeoPlayer, IncidentGroup } from '../types';
import { DEFAULT_FILTERS, type GlobalFilters } from './filters.store';
import {
  applyIncidentStatusToList,
  countriesFromGeo,
  enrichSessionsWithGeo,
  filterGeoPlayers,
  filterIncidents,
  filterSessions,
  geoByPlayer,
  normalizeGhostSample,
  platformsFromSessions,
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

describe('geoByPlayer', () => {
  it('maps player_id to geo info, first occurrence wins', () => {
    const items = [
      geo({ player_id: 'p1', city: 'Lima', country_code: 'PE' }),
      geo({ player_id: 'p1', city: 'Cusco', country_code: 'PE' }),
      geo({ player_id: 'p2', city: 'Bogota', country_code: 'CO' }),
    ];
    const map = geoByPlayer(items);
    expect(map.p1.city).toBe('Lima');
    expect(map.p2.country_code).toBe('CO');
  });
});

describe('enrichSessionsWithGeo', () => {
  it('fills only missing fields from the geo join', () => {
    const byPlayer = { p1: { city: 'Lima', country: 'Peru', country_code: 'PE', display_name: 'Ana' } };
    const sessions: Array<Record<string, unknown>> = [
      { player_id: 'p1', session_id: 's1', city: 'Arequipa' }, // city already set, keep it
      { player_id: 'p1', session_id: 's2' },
      { player_id: 'pX', session_id: 's3' }, // no geo -> untouched
    ];
    const out = enrichSessionsWithGeo(sessions, byPlayer);
    expect(out[0].city).toBe('Arequipa');
    expect(out[0].country).toBe('Peru');
    expect(out[1].city).toBe('Lima');
    expect(out[2]).toEqual({ player_id: 'pX', session_id: 's3' });
  });

  it('returns the same object reference for rows without geo (no needless copy)', () => {
    const row = { player_id: 'pX', session_id: 's3' };
    const out = enrichSessionsWithGeo([row], {});
    expect(out[0]).toBe(row);
  });
});

describe('filterSessions', () => {
  const base = filters({});

  it('returns all sessions when no filters are set', () => {
    const sessions = [{ session_id: 'a' }, { session_id: 'b' }];
    expect(filterSessions(sessions, base)).toHaveLength(2);
  });

  it('keeps a session whose visited scenes include the filter scene', () => {
    const sessions = [
      { session_id: 'a', scenes_visited: ['OdiseaExterior', 'OdiseaInterior'] },
      { session_id: 'b', scenes_visited: ['OdiseaInterior'] },
    ];
    const out = filterSessions(sessions, filters({ scene: 'OdiseaExterior' }));
    expect(out.map((s) => s.session_id)).toEqual(['a']);
  });

  it('keeps scene-less sessions regardless of the scene filter', () => {
    const sessions = [{ session_id: 'a' }]; // no scene info
    expect(filterSessions(sessions, filters({ scene: 'OdiseaExterior' }))).toHaveLength(1);
  });

  it('filters by normalized platform (win -> windows)', () => {
    const sessions = [
      { session_id: 'a', platform: 'win64' },
      { session_id: 'b', platform: 'android' },
    ];
    const out = filterSessions(sessions, filters({ platform: 'windows' }));
    expect(out.map((s) => s.session_id)).toEqual(['a']);
  });

  it('keeps platform-less sessions when a platform filter is set', () => {
    const sessions = [{ session_id: 'srv' }]; // no platform detected
    expect(filterSessions(sessions, filters({ platform: 'windows' }))).toHaveLength(1);
  });

  it('filters by country code via the geo join when the row lacks one', () => {
    const sessions = [
      { session_id: 'a', player_id: 'p1' },
      { session_id: 'b', player_id: 'p2' },
    ];
    const byPlayer = { p1: { country_code: 'PE' }, p2: { country_code: 'US' } };
    const out = filterSessions(sessions, filters({ country: 'PE' }), byPlayer);
    expect(out.map((s) => s.session_id)).toEqual(['a']);
  });

  it('drops sessions shorter than minDurationSec but never live ones', () => {
    const sessions = [
      { session_id: 'short', duration: 5 },
      { session_id: 'long', duration: 120 },
      { session_id: 'live', duration: 0, live: true },
    ];
    const out = filterSessions(sessions, filters({ minDurationSec: 60 }));
    expect(out.map((s) => s.session_id)).toEqual(['long', 'live']);
  });
});

describe('platformsFromSessions', () => {
  it('counts normalized platforms, sorted by count desc, skipping unknown', () => {
    const sessions = [
      { platform: 'win64' },
      { platform: 'windows' },
      { platform: 'android' },
      { platform: 'html5' },
      {}, // no platform -> skipped
    ];
    expect(platformsFromSessions(sessions)).toEqual([
      { platform: 'windows', count: 2 },
      { platform: 'android', count: 1 },
      { platform: 'web', count: 1 },
    ]);
  });
});

describe('normalizeGhostSample', () => {
  it('flattens a nested player heartbeat (position array -> pos_x/y/z)', () => {
    const out = normalizeGhostSample({
      timestamp: 100,
      player: { fps: 42, memory_mb: 256, position: [1, 2, 3], scene: 'OdiseaExterior', platform: 'windows' },
    });
    expect(out).toMatchObject({
      timestamp: 100,
      fps: 42,
      memory_mb: 256,
      pos_x: 1,
      pos_y: 2,
      pos_z: 3,
      scene: 'OdiseaExterior',
      platform: 'windows',
    });
  });

  it('prefers already-flat fields and falls back to defaults', () => {
    const out = normalizeGhostSample({ pos_x: 7, fps: 30 });
    expect(out).toMatchObject({ pos_x: 7, pos_y: 0, pos_z: 0, fps: 30, scene: '?', platform: '?' });
  });
});
