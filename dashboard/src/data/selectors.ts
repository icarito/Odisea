import type { GeoPlayer, IncidentGroup, IncidentStatus } from '../types';
import { getPlatform, sessionDuration, sessionScenes } from '../lib/filters';
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

// Aplica un cambio de estado optimista a UNA lista de incidentes cacheada.
// `keyStatus` es el status por el que esa query está filtrada ('all' = sin
// filtro). Devuelve la lista con el item actualizado y, si su nuevo status ya no
// matchea el filtro de esa query, removido. Pura para poder testear el corazón
// de la mutación optimista sin montar react-query.
export function applyIncidentStatusToList(
  data: IncidentGroup[],
  id: string,
  status: IncidentStatus,
  keyStatus: IncidentStatus | 'all',
): IncidentGroup[] {
  return data
    .map((i) => (i.id === id ? { ...i, status } : i))
    .filter((i) => keyStatus === 'all' || i.status === keyStatus);
}

// --- Sesiones (vista History) -----------------------------------------------

export interface GeoInfo {
  city?: string;
  country?: string;
  country_code?: string;
  display_name?: string;
  color?: string;
}

// Mapa player_id -> datos de geo (primera ocurrencia gana), para unir ubicación
// y tag a las filas de sesión que sólo traen player_id.
export function geoByPlayer(items: GeoPlayer[]): Record<string, GeoInfo> {
  const map: Record<string, GeoInfo> = {};
  for (const g of items) {
    if (g.player_id && !map[g.player_id]) {
      map[g.player_id] = {
        city: g.city,
        country: g.country,
        country_code: g.country_code,
        display_name: g.display_name,
        color: g.color,
      };
    }
  }
  return map;
}

// Las escenas que "tocó" una sesión: el campo directo (escena en vuelo o de la
// fila) o, si no, las derivadas del recorrido. Mismo criterio que el clásico.
function sessionSceneList(s: Record<string, unknown>): string[] {
  const direct = (s as { player?: { scene?: string }; scene?: string }).player?.scene
    ?? (s as { scene?: string }).scene;
  return direct ? [direct] : sessionScenes(s);
}

// Une geo a las filas de sesión (sólo rellena lo que la fila no trae ya).
export function enrichSessionsWithGeo<T extends Record<string, unknown>>(
  sessions: T[],
  byPlayer: Record<string, GeoInfo>,
): T[] {
  return sessions.map((s) => {
    const pid = s.player_id as string | undefined;
    const geo = pid ? byPlayer[pid] : undefined;
    if (!geo) return s;
    return {
      ...s,
      city: s.city || geo.city,
      country: s.country || geo.country,
      country_code: s.country_code || geo.country_code,
      display_name: s.display_name || geo.display_name,
      color: s.color || geo.color,
    };
  });
}

// Aplica los filtros globales a las sesiones. Replica la semántica del clásico:
// - escena: pasa si la sesión no tiene escenas o incluye la elegida.
// - plataforma: pasa si no se detecta plataforma o coincide (filtro simple).
// - país: por country_code de la fila o del join de geo.
// - duración mínima: nunca filtra sesiones live (en vuelo, duración 0).
export function filterSessions<T extends Record<string, unknown>>(
  sessions: T[],
  f: GlobalFilters,
  byPlayer: Record<string, GeoInfo> = {},
): T[] {
  const country = f.country.toUpperCase();
  const platform = f.platform.toLowerCase();
  return sessions.filter((s) => {
    if (f.scene) {
      const scenesOf = sessionSceneList(s);
      if (scenesOf.length > 0 && !scenesOf.includes(f.scene)) return false;
    }
    if (platform) {
      const p = (getPlatform(s) || '').toLowerCase();
      if (p && p !== platform) return false;
    }
    if (country) {
      const pid = s.player_id as string | undefined;
      const cc = String(s.country_code || (pid ? byPlayer[pid]?.country_code : '') || '').toUpperCase();
      if (cc !== country) return false;
    }
    if (!s.live && f.minDurationSec > 0 && sessionDuration(s) < f.minDurationSec) return false;
    return true;
  });
}

// Lista de plataformas presentes en las sesiones, con su conteo, orden desc.
// Alimenta el selector de plataforma de la vista History.
export function platformsFromSessions(sessions: Array<Record<string, unknown>>): Array<{ platform: string; count: number }> {
  const by = new Map<string, number>();
  for (const s of sessions) {
    const p = getPlatform(s);
    if (!p) continue;
    by.set(p, (by.get(p) || 0) + 1);
  }
  return [...by.entries()].map(([platform, count]) => ({ platform, count })).sort((a, b) => b.count - a.count);
}

// Normaliza una muestra ghost (player anidado) al heartbeat plano que espera
// SessionPlayback. Pura para poder testear el mapeo de posición/fps/memoria.
export function normalizeGhostSample(hb: Record<string, any>): {
  timestamp: number; fps: number; memory_mb: number;
  pos_x: number; pos_y: number; pos_z: number;
  scene: string; platform: string; engine_version: string;
} {
  const p = hb.player || {};
  const pos = p.position;
  return {
    timestamp: hb.timestamp ?? 0,
    fps: hb.fps ?? p.fps ?? 0,
    memory_mb: hb.memory_mb ?? p.memory_mb ?? 0,
    pos_x: hb.pos_x ?? pos?.[0] ?? 0,
    pos_y: hb.pos_y ?? p.position?.[1] ?? pos?.[1] ?? 0,
    pos_z: hb.pos_z ?? pos?.[2] ?? 0,
    scene: hb.scene ?? p.scene ?? '?',
    platform: hb.platform ?? p.platform ?? '?',
    engine_version: hb.engine_version ?? hb.godot_version ?? p.engine_version ?? '?',
  };
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
