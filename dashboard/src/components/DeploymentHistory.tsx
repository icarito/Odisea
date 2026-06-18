import React, { useMemo } from 'react';
import { GitCommit as GitCommitIcon, CheckCircle2, XCircle, Loader2, CircleDashed, Rocket, ExternalLink } from 'lucide-react';
import { isDashboardSession } from '../lib/filters';

// Shapes mirror the GitHub REST API responses we consume. They are loaded in
// App.tsx and passed down already-trimmed.
export type GitCommit = {
  sha: string;
  date: string;
  message: string;
  additions?: number;
  deletions?: number;
  files?: Array<{
    filename: string;
    status: string;
    additions: number;
    deletions: number;
  }>;
};

export type WorkflowRun = {
  id: number;
  name: string;
  status: string; // queued | in_progress | completed
  conclusion: string | null; // success | failure | cancelled | null
  head_sha: string;
  created_at: string;
  html_url: string;
};

// A live (non-GitHub) published build coming from /health — the nightly/canary
// the central server last announced.
export type PublishedBuild = {
  game_version?: string;
  git_commit?: string;
  build_id?: string;
  build_channel?: string;
  timestamp?: number;
};

interface DeploymentHistoryProps {
  // Already filter-respecting session list (filteredDashboardSessions).
  sessions: any[];
  commits: GitCommit[];
  workflowRuns?: WorkflowRun[];
  // Live published build + dashboard deploy from /health.
  latestPublished?: PublishedBuild | null;
  dashboardVersion?: string | null;
  dashboardDeployedAt?: number | null;
}

const fpsColor = (fps: number) => {
  if (fps > 45) return '#3fb950';
  if (fps >= 30) return '#d29922';
  return '#f85149';
};

const formatDate = (iso: string | number | undefined): string => {
  if (!iso) return '—';
  const d = typeof iso === 'number' ? new Date(iso * 1000) : new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';
  return new Intl.DateTimeFormat('en-GB', {
    day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false,
  }).format(d);
};

// CI status -> badge color + icon. Covers both completed conclusions and the
// in-flight statuses (queued/in_progress).
const RunBadge = ({ run }: { run: WorkflowRun }) => {
  let color = '#8b949e';
  let Icon = CircleDashed;
  let label = run.conclusion || run.status;
  if (run.status !== 'completed') {
    color = '#d29922';
    Icon = Loader2;
    label = run.status === 'in_progress' ? 'running' : run.status;
  } else if (run.conclusion === 'success') {
    color = '#3fb950';
    Icon = CheckCircle2;
    label = 'passing';
  } else if (run.conclusion === 'failure') {
    color = '#f85149';
    Icon = XCircle;
    label = 'failing';
  }
  return (
    <a
      href={run.html_url}
      target="_blank"
      rel="noopener noreferrer"
      title={`${run.name} · ${run.conclusion || run.status} · ${formatDate(run.created_at)}`}
      className="inline-flex items-center gap-1 border-2 border-black bg-bg-primary px-1.5 py-0.5 text-[0.5rem] font-black uppercase tracking-wide hover:bg-accent/10"
      style={{ color }}
    >
      <Icon size={9} className={run.status !== 'completed' ? 'animate-spin' : ''} />
      <span className="max-w-[7rem] truncate normal-case text-text-muted">{run.name}</span>
      <span>{label}</span>
    </a>
  );
};

// Per-version (per-commit) aggregate of the FILTERED sessions whose start_time
// falls in the window [thisCommit, nextNewerCommit). Honest: when no filtered
// session lands in a version's window we show "sin datos" rather than zeros.
type VersionStat = { sessions: number; avgFps: number; lowPct: number };

export const DeploymentHistory: React.FC<DeploymentHistoryProps> = ({
  sessions,
  commits,
  workflowRuns = [],
  latestPublished,
  dashboardVersion,
  dashboardDeployedAt,
}) => {
  // Commits newest-first with a unix timestamp for windowing.
  const orderedCommits = useMemo(() => (
    commits
      .map((c) => ({ ...c, ts: Math.floor(new Date(c.date).getTime() / 1000) }))
      .filter((c) => Number.isFinite(c.ts) && c.ts > 0)
      .sort((a, b) => b.ts - a.ts)
  ), [commits]);

  // Filtered dashboard sessions with a usable start time, sorted ascending so we
  // can bucket them into version windows.
  const cleanSessions = useMemo(() => (
    sessions
      .filter(isDashboardSession)
      .map((s) => ({ ts: Number(s.start_time) || 0, fps: Number(s.avg_fps) || 0 }))
      .filter((s) => s.ts > 0)
  ), [sessions]);

  // For each commit, the sessions that ran on that version (between this commit
  // and the next newer one). Respects the upstream filters via `sessions`.
  const statsByCommit = useMemo(() => {
    const map = new Map<string, VersionStat>();
    for (let i = 0; i < orderedCommits.length; i++) {
      const from = orderedCommits[i].ts;
      const to = i > 0 ? orderedCommits[i - 1].ts : Infinity; // newer bound
      const inWindow = cleanSessions.filter((s) => s.ts >= from && s.ts < to);
      const fpsVals = inWindow.map((s) => s.fps).filter((n) => Number.isFinite(n) && n > 0);
      const avgFps = fpsVals.length ? fpsVals.reduce((a, b) => a + b, 0) / fpsVals.length : 0;
      const lowPct = inWindow.length
        ? inWindow.filter((s) => s.fps > 0 && s.fps < 30).length * 100 / inWindow.length
        : 0;
      map.set(orderedCommits[i].sha, { sessions: inWindow.length, avgFps, lowPct });
    }
    return map;
  }, [orderedCommits, cleanSessions]);

  // The few most-recent CI runs overall, for a compact "latest activity" strip.
  // The full per-workflow outcome lives embedded in each version row below, so
  // this stays small (3) to avoid duplicating that information.
  const latestRuns = useMemo(() => (
    [...workflowRuns]
      .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())
      .slice(0, 3)
  ), [workflowRuns]);

  // CI runs keyed by head sha, so each commit row can show its build outcome.
  const runsBySha = useMemo(() => {
    const map = new Map<string, WorkflowRun[]>();
    for (const run of workflowRuns) {
      const key = (run.head_sha || '').slice(0, 12);
      if (!key) continue;
      const list = map.get(key);
      if (list) list.push(run);
      else map.set(key, [run]);
    }
    return map;
  }, [workflowRuns]);

  const runsForSha = (sha: string) => runsBySha.get(sha.slice(0, 12)) || [];

  // Only what's live right now: the published build (from /health) and the
  // currently-served dashboard. We intentionally drop the long GitHub
  // deployment history — that detail lives in the version rows below.
  const deployRows = useMemo(() => {
    const rows: Array<{
      key: string; environment: string; sha?: string; date: string | number | undefined;
      state?: string | null; url?: string | null;
    }> = [];
    if (latestPublished?.git_commit || latestPublished?.timestamp) {
      rows.push({
        key: 'live-published',
        environment: latestPublished.build_channel || 'build',
        sha: latestPublished.git_commit,
        date: latestPublished.timestamp,
        state: 'live',
      });
    }
    if (dashboardVersion || dashboardDeployedAt) {
      rows.push({
        key: 'live-dashboard',
        environment: 'dashboard',
        sha: dashboardVersion || undefined,
        date: dashboardDeployedAt || undefined,
        state: 'live',
      });
    }
    return rows;
  }, [latestPublished, dashboardVersion, dashboardDeployedAt]);

  return (
    <div className="flex flex-col gap-4 p-1">
      {/* Compact "latest CI activity" strip — just the most recent runs. The
          full per-version outcome is embedded in each version row below. */}
      {latestRuns.length > 0 && (
        <div>
          <div className="mb-1.5 text-[0.625rem] font-black uppercase tracking-widest text-accent">Últimas corridas</div>
          <div className="flex flex-wrap gap-1.5">
            {latestRuns.map((run) => <RunBadge key={run.id} run={run} />)}
          </div>
        </div>
      )}

      {/* What's live right now — published build + current dashboard. */}
      {deployRows.length > 0 && (
        <div>
          <div className="mb-1.5 flex items-center gap-1.5 text-[0.625rem] font-black uppercase tracking-widest text-accent">
            <Rocket size={11} /> En vivo
          </div>
          <div className="flex flex-col gap-1">
            {deployRows.map((d) => (
              <div key={d.key} className="flex items-center justify-between gap-2 border-2 border-black bg-bg-primary px-2 py-1 text-[0.625rem]">
                <div className="flex min-w-0 items-center gap-1.5">
                  <span className="shrink-0 border border-black bg-accent/15 px-1 font-black uppercase text-accent">{d.environment}</span>
                  {d.sha && <span className="font-mono text-text-muted">{d.sha.slice(0, 7)}</span>}
                  {d.state === 'live' && (
                    <span className="inline-flex items-center gap-1 text-success">
                      <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-success" />live
                    </span>
                  )}
                  {d.state && d.state !== 'live' && (
                    <span className="text-text-muted">{d.state}</span>
                  )}
                </div>
                <div className="flex shrink-0 items-center gap-1.5">
                  <span className="text-text-muted">{formatDate(d.date)}</span>
                  {d.url && (
                    <a href={d.url} target="_blank" rel="noopener noreferrer" className="text-accent hover:text-text-primary" title="Abrir deployment">
                      <ExternalLink size={10} />
                    </a>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Git history — commit messages + dates, annotated with the FILTERED
          performance stats for the sessions that ran on that version. */}
      <div>
        <div className="mb-1.5 flex items-center gap-1.5 text-[0.625rem] font-black uppercase tracking-widest text-accent">
          <GitCommitIcon size={11} /> Historial de versiones
        </div>
        {orderedCommits.length === 0 ? (
          <div className="text-xs italic text-text-muted">Sin historial de commits</div>
        ) : (
          <div className="flex flex-col gap-1">
            {orderedCommits.map((c) => {
              const stat = statsByCommit.get(c.sha);
              const ciRuns = runsForSha(c.sha);
              const hasData = !!stat && stat.sessions > 0;
              return (
                <div key={c.sha} className="border-2 border-black bg-bg-primary px-2 py-1.5 text-[0.625rem]">
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0 flex-1">
                      <div className="truncate text-text-primary" title={c.message}>{c.message.split('\n')[0]}</div>
                      <div className="mt-0.5 flex items-center gap-1.5 text-text-muted">
                        <span className="font-mono text-[#d29922]">{c.sha.slice(0, 7)}</span>
                        <span>·</span>
                        <span>{formatDate(c.date)}</span>
                      </div>
                    </div>
                    {/* Filtered version stats: avg FPS + session count. */}
                    <div className="shrink-0 text-right">
                      {hasData ? (
                        <>
                          <div className="text-sm font-black leading-none" style={{ color: fpsColor(stat!.avgFps) }}>
                            {stat!.avgFps.toFixed(1)}
                          </div>
                          <div className="text-[0.5rem] uppercase text-text-muted">
                            {stat!.sessions} ses · {stat!.lowPct.toFixed(0)}% low
                          </div>
                        </>
                      ) : (
                        <div className="text-[0.5rem] uppercase italic text-text-muted/60">sin datos</div>
                      )}
                    </div>
                  </div>
                  {ciRuns.length > 0 && (
                    <div className="mt-1 flex flex-wrap gap-1">
                      {ciRuns.map((run) => <RunBadge key={run.id} run={run} />)}
                    </div>
                  )}
                  {c.files && (
                    <div className="mt-1.5 border-t border-black/40 pt-1">
                      <div className="mb-1 flex items-center gap-2 text-[0.5rem] font-black uppercase text-text-muted">
                        <span>{c.files.length} archivo{c.files.length === 1 ? '' : 's'}</span>
                        <span className="text-success">+{c.additions || 0}</span>
                        <span className="text-danger">−{c.deletions || 0}</span>
                      </div>
                      <div className="flex flex-col gap-0.5">
                        {c.files.slice(0, 6).map((file) => (
                          <div key={file.filename} className="flex min-w-0 items-center gap-1 font-mono text-[0.5rem]">
                            <span className={`w-3 shrink-0 font-black uppercase ${
                              file.status === 'added' ? 'text-success'
                                : file.status === 'removed' ? 'text-danger'
                                  : 'text-[#d29922]'
                            }`}>
                              {file.status.slice(0, 1)}
                            </span>
                            <span className="min-w-0 flex-1 truncate text-text-muted" title={file.filename}>{file.filename}</span>
                            <span className="shrink-0 text-success">+{file.additions}</span>
                            <span className="shrink-0 text-danger">−{file.deletions}</span>
                          </div>
                        ))}
                        {c.files.length > 6 && (
                          <div className="text-[0.5rem] italic text-text-muted">+{c.files.length - 6} archivos más</div>
                        )}
                      </div>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
};
