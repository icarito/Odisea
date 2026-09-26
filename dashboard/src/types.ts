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
  // Fase del juego reportada en cada heartbeat: loading | boot | menu | paused
  // | play. Solo `play` cuenta para stats de rendimiento. Ausente en
  // heartbeats viejos (se trata como play).
  phase?: string;
  paused?: boolean;
  // Progreso de la transicion de SceneManager en curso (solo presente durante
  // phase == "loading"). path/current_scene son res://... completos.
  transition?: {
    stage?: string;
    path?: string;
    current_scene?: string;
    elapsed_ms?: number;
    progress?: number;
    error?: string;
  };
  perf?: {
    dc: number;
    obj: number;
    vtx: number;
    nodes: number;
  };
  // Diagnostico de render en web (ANNAV2_Thread_Web.gd); user_agent solo
  // presente en builds posteriores a feat(telemetry) user_agent.
  render_diag?: {
    user_agent?: string;
    [key: string]: any;
  };
}

// Eventos discretos de telemetria v2. El juego los encola con seq monotono por
// sesion; el central los difunde por el WS /events y los persiste en
// session_events. `t`/`timestamp` puede venir en ms o en segundos segun el
// emisor, por eso los consumidores normalizan.
export type TelemetryEventType =
  | 'session_start'
  | 'scene_enter'
  | 'scene_change'
  | 'death'
  | 'respawn'
  | 'pause'
  | 'resume';

export interface TelemetryEvent {
  type: TelemetryEventType | string;
  player_id?: string;
  session_id?: string;
  scene?: string;
  timestamp: number;
  seq?: number;
  data?: Record<string, any>;
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
  // Cola de eventos discretos pendientes, drenada en cada heartbeat v2.
  events?: TelemetryEvent[];
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

// GET /ghosts/load_times?days=N (solo lectura): percentiles de load_ms por
// escena destino (eventos scene_enter) + boot_ms de session_start. p50/p90
// pueden ser null cuando no hay muestras para esa escena.
export interface LoadTimeStat {
  scene: string;
  n: number;
  p50: number | null;
  p90: number | null;
}

export interface LoadTimesResponse {
  days: number;
  scenes: LoadTimeStat[];
  boot: { n: number; p50: number | null; p90: number | null };
}
