export interface PlayerState {
  position: [number, number, number];
  velocity: [number, number, number];
  yaw: number;
  pitch: number;
  roll: number;
  mode: string;
  scene: string;
  zone: string;
  tick: number;
  fps: number;
  memory_mb: number;
  // False when the game window is backgrounded; telemetry is throttled and
  // FPS/perf alerts are suppressed for these samples.
  focused?: boolean;
  perf?: {
    dc: number;
    obj: number;
    vtx: number;
    nodes: number;
  };
}

export interface Heartbeat {
  player_id: string;
  session_id: string;
  host: string;
  platform: string;
  godot_version: string;
  game_version: string;
  git_commit?: string;
  build_id?: string;
  build_channel?: string;
  official_host?: string;
  official_build?: boolean;
  intake_mode?: 'admin' | 'ingest' | 'telemetry';
  display_name?: string;
  color?: string;
  notes?: string;
  player: PlayerState;
  timestamp: number;
}

export type HeartbeatMap = Record<string, Heartbeat>;

// Top-level dashboard tabs. Shared so components (e.g. Viewport3D) can type
// their setActiveTab prop against the same union instead of a loose `string`.
export type Tab = 'dashboard' | 'scenes' | 'players' | 'analysis' | 'replays' | 'live' | 'heatmap' | 'history' | 'mapa';

export interface Alert {
  id: string;
  type: 'fps' | 'memory' | 'softlock' | 'disconnect' | 'stale' | 'low_fps' | 'memory_leak';
  message: string;
  timestamp: number;
  playerId: string;
}

export interface GeoPlayer {
  player_id: string;
  session_id: string;
  last_seen: number;
  country: string;
  country_code: string;
  city: string;
  latitude: number;
  longitude: number;
  display_name?: string;
  color?: string;
  status: 'connected' | 'recent' | 'old';
  hits?: number;
  historical?: boolean;
  player_count?: number;
}

export interface Tag {
  id: string;
  label: string;
  category?: string;
  color?: string;
}

// --- Incidentes (IA incident-first, backend /incidents*) ----------------------
// Un incidente agrupa ocurrencias del mismo problema (mismo tipo + escena + zona
// + cluster espacial) para triage: open -> known/resolved/dismissed.
export type IncidentType = 'low_fps' | 'hotzone';
export type IncidentStatus = 'open' | 'known' | 'resolved' | 'dismissed';

export interface IncidentGroup {
  id: string;
  type: IncidentType;
  scene: string;
  zone: string;
  spatial_cluster_x: number;
  spatial_cluster_z: number;
  status: IncidentStatus;
  count: number;
  first_seen: number;
  last_seen: number;
  builds_seen: string[];
}

export interface IncidentOccurrence {
  id: string;
  group_id: string;
  player_id: string;
  session_id: string;
  fps: number;
  timestamp: number;
  scene: string;
  build_id: string;
}

// Una muestra de telemetría (ghost) usada por la vista de investigación:
// timeline de FPS + trayectoria sobre el floorplan de la escena.
export interface SessionSample {
  timestamp: number;
  fps: number;
  pos_x: number;
  pos_y: number;
  pos_z: number;
  scene: string;
  zone: string;
  mode: string;
  memory_mb: number;
}

// Proyección del floorplan de una escena (world bounds + escala) para dibujar
// la trayectoria del jugador en 2D.
export interface FloorplanProjection {
  world_min_x: number;
  world_min_z: number;
  world_max_x: number;
  world_max_z: number;
  scale: number;
}
