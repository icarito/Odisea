type BuildMeta = {
  game_version?: string;
  git_commit?: string;
  build_id?: string;
  build_channel?: string;
};

const short = (value?: string, length = 7): string => (
  typeof value === 'string' ? value.trim().slice(0, length) : ''
);

// Filas de /ghosts/sessions no traen build_id (solo game_version/git_commit/
// build_channel); el numero de build viaja embebido en game_version
// ("0.5.0-nightly.749+ad11b29"). Fallback cuando no hay build_id explicito.
const buildIdFromVersion = (gameVersion?: string): string => {
  const match = typeof gameVersion === 'string' ? gameVersion.match(/nightly\.(\d+)/) : null;
  return match ? match[1] : '';
};

export interface BuildVersionInfo {
  channel: string; // 'nightly' | 'dev' | 'release' | ...
  version: string; // '#749', o el game_version completo si no hay build_id
  hash: string;    // hash corto, solo para tooltip/detalle
}

// Version legible: canal (tag) + numero de build. El hash queda aparte
// (`hash`) para mostrarlo solo en tooltip/detalle, no en la etiqueta principal.
export const buildVersionInfo = (build?: BuildMeta | null): BuildVersionInfo | null => {
  if (!build) return null;
  const channel = (build.build_channel || '').trim().toLowerCase();
  const commit = short(build.git_commit);
  const gameVersion = (build.game_version || '').trim();
  const buildId = short(build.build_id, 12) || buildIdFromVersion(gameVersion);
  if (!channel && !commit && !buildId && !gameVersion) return null;
  const version = buildId
    ? `#${buildId}`
    : (gameVersion && gameVersion !== 'unknown' ? gameVersion : '');
  if (!channel && !version) return null;
  return { channel: channel || 'dev', version, hash: commit };
};

// Etiqueta plana "canal #build" para donde no hace falta separar tag/version
// (p.ej. texto simple, sin markup). Preferir buildVersionInfo en UI nueva.
export const buildLabel = (build?: BuildMeta | null): string => {
  const info = buildVersionInfo(build);
  if (!info) return '';
  return [info.channel, info.version].filter(Boolean).join(' ');
};
