// Shared, global telemetry filters.
//
// These were previously scattered/duplicated across App.tsx and the backend.
// Centralizing them here keeps the `server`-platform exclusion, scene parsing,
// and warmup stripping consistent for every consumer.

export const KNOWN_PLATFORMS = ['server', 'android', 'linux', 'windows', 'macos', 'web'];

// First seconds of every session (scene load, GC, chunk streaming) skew FPS and
// memory. We strip this window from per-heartbeat stats so the runtime data
// reflects steady-state behavior, not warmup. Bumped 10 -> 13 because 10s still
// caught the tail of scene bootup.
export const WARMUP_SECONDS = 13;
export const UNCAPPED_FPS_THRESHOLD = 240;

export const normalizePlatform = (value: any): string | null => {
  if (typeof value !== 'string' || value.trim() === '') return null;
  const normalized = value.trim().toLowerCase();
  if (['html5', 'webgl', 'browser'].includes(normalized)) return 'web';
  if (['darwin', 'osx', 'mac'].includes(normalized)) return 'macos';
  if (['win', 'win32', 'win64'].includes(normalized)) return 'windows';
  if (['x11', 'linuxbsd', 'linux_x11'].includes(normalized)) return 'linux';
  return normalized;
};

export const getPlatform = (item: any): string | null => (
  normalizePlatform(item?.platform ?? item?.player?.platform)
);

// A "dashboard" session is a real client run: not the headless server.
// Server builds report uncapped FPS (hundreds/thousands), while real players
// with high-refresh monitors (144Hz, 240Hz) can legitimately exceed 65 FPS.
// We use platform + auth token to distinguish server from real clients,
// rather than an arbitrary FPS cap.
export const isDashboardSession = (session: any): boolean => {
  const platform = getPlatform(session);
  // Only drop explicit server platform (headless builds report as 'server')
  if (platform === 'server') return false;
  // A real client with auth token is always a dashboard session
  if (session?.token_mode) return true;
  // Live sessions (still in flight) are kept regardless of scene: a player who
  // just spawned may still be in `boot` or report an empty scene for a tick, and
  // dropping them here would make them vanish from the live globe. The
  // useful-scene gate only excludes historical/bootup-only sessions.
  if (session?.live) return true;
  const scenes = sessionScenes(session).filter((scene) => {
    const normalized = scene.trim().toLowerCase();
    return isUsefulSceneName(scene) && normalized !== 'boot';
  });
  return scenes.length > 0;
};

// Session length in seconds. Prefer the persisted `duration`; fall back to
// end_time - start_time when only timestamps are present.
export const sessionDuration = (session: any): number => {
  const duration = Number(session?.duration);
  if (Number.isFinite(duration) && duration > 0) return duration;
  const start = Number(session?.start_time);
  const end = Number(session?.end_time);
  if (Number.isFinite(start) && Number.isFinite(end) && end > start) return end - start;
  return 0;
};

export const sessionScenes = (session: any): string[] => {
  if (Array.isArray(session?.scenes_visited)) return session.scenes_visited.filter(Boolean);
  if (typeof session?.scenes_visited === 'string') {
    return session.scenes_visited.split(',').map((s: string) => s.trim()).filter(Boolean);
  }
  return session?.scene ? [session.scene] : [];
};

export const isUsefulSceneName = (scene: any): scene is string => {
  if (typeof scene !== 'string') return false;
  const normalized = scene.trim().toLowerCase();
  return Boolean(normalized) && !['?', 'unknown', 'desconocida', 'desconocido', 'undefined', 'null'].includes(normalized);
};

// Memory sometimes arrives as 0 or undefined (notably web peers via
// ANNAV2_Thread_Web.gd). Treat that as "no report" so we don't plot a fake-zero
// line — distinct from a genuine low-memory reading.
export const hasMemReport = (value: any): value is number => (
  typeof value === 'number' && Number.isFinite(value) && value > 0
);

export const isLikelyUncappedFps = (value: unknown): boolean => {
  const fps = Number(value);
  return Number.isFinite(fps) && fps > UNCAPPED_FPS_THRESHOLD;
};

export const formatFpsLabel = (value: unknown): string => {
  const fps = Number(value) || 0;
  const rounded = Math.round(fps);
  return isLikelyUncappedFps(fps) ? `${rounded} FPS uncapped` : `${rounded} FPS`;
};

// Drop heartbeats within WARMUP_SECONDS of the session's first sample. Rows must
// carry a numeric `timestamp` (seconds). If stripping would empty the set (very
// short session), the original rows are returned unchanged.
export function stripWarmup<T extends { timestamp?: number }>(
  rows: T[],
  warmupSeconds: number = WARMUP_SECONDS,
): T[] {
  if (!Array.isArray(rows) || rows.length === 0) return rows;
  const start = rows.reduce((min, r) => {
    const t = Number(r.timestamp);
    return Number.isFinite(t) && t < min ? t : min;
  }, Number.POSITIVE_INFINITY);
  if (!Number.isFinite(start)) return rows;
  const cutoff = start + warmupSeconds;
  const kept = rows.filter((r) => Number(r.timestamp) >= cutoff);
  return kept.length > 0 ? kept : rows;
}
