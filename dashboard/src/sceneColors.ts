// Deterministic per-scene colors, shared across the dashboard so the timeline,
// charts, and bird's-eye trail all agree on what color a scene is.

const KNOWN: Record<string, string> = {
  Dome_Crio: '#3fb950',      // green
  OdiseaExterior: '#d29922', // amber
  ScaffoldOrbit: '#a371f7',  // purple
  Unknown: '#6b7280',
  '?': '#6b7280',
};

// Fallback palette for scenes we don't have a fixed color for. Picked by hashing
// the name so the same scene always lands on the same color within a session.
const PALETTE = [
  '#f778ba', '#56d364', '#e3b341', '#79c0ff', '#ff7b72',
  '#d2a8ff', '#ffa657', '#39c5cf', '#bc8cff', '#7ee787',
];

function hash(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return Math.abs(h);
}

export function sceneColor(scene: string | undefined | null): string {
  if (!scene) return KNOWN.Unknown;
  if (KNOWN[scene]) return KNOWN[scene];
  return PALETTE[hash(scene) % PALETTE.length];
}
