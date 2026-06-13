type BuildMeta = {
  game_version?: string;
  git_commit?: string;
  build_id?: string;
  build_channel?: string;
};

const short = (value?: string, length = 7): string => (
  typeof value === 'string' ? value.trim().slice(0, length) : ''
);

export const buildLabel = (build?: BuildMeta | null): string => {
  if (!build) return '';
  const channel = (build.build_channel || '').trim().toLowerCase();
  const commit = short(build.git_commit);
  const buildId = short(build.build_id, 12);
  const gameVersion = (build.game_version || '').trim();

  if (channel === 'release' && gameVersion && gameVersion !== 'unknown') {
    return `${gameVersion}${commit ? `@${commit}` : ''}`;
  }
  if (commit) return `${channel || 'dev'}@${commit}`;
  if (buildId) return `${channel || 'dev'}#${buildId}`;
  if (channel) return channel;
  return gameVersion && gameVersion !== 'unknown' ? gameVersion : '';
};
