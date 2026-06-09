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
}

export interface Heartbeat {
  player_id: string;
  session_id: string;
  host: string;
  platform: string;
  godot_version: string;
  game_version: string;
  player: PlayerState;
  timestamp: number;
}

export type HeartbeatMap = Record<string, Heartbeat>;

export interface Alert {
  id: string;
  type: 'fps' | 'memory' | 'softlock' | 'disconnect' | 'stale' | 'low_fps' | 'memory_leak';
  message: string;
  timestamp: number;
  playerId: string;
}
