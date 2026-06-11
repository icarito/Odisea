import { useMemo, useState } from 'react';
import { ChevronDown, ChevronRight, ChevronUp } from 'lucide-react';

export const HistoricalTable = ({ sessions, onSelectSession }: { sessions: any[], onSelectSession: (s: any) => void }) => {
  const [sortDir, setSortDir] = useState<'desc' | 'asc'>('desc');
  const [sortKey, setSortKey] = useState<'date' | 'fps'>('date');

  const sortedSessions = useMemo(() => {
    return [...sessions].sort((a, b) => {
      const aValue = sortKey === 'date' ? Number(a.start_time) || 0 : Number(a.avg_fps) || 0;
      const bValue = sortKey === 'date' ? Number(b.start_time) || 0 : Number(b.avg_fps) || 0;
      return sortDir === 'desc' ? bValue - aValue : aValue - bValue;
    });
  }, [sessions, sortDir, sortKey]);

  const formatDate = (ts: number) => {
    if (!ts) return 'Unknown date';
    const parts = new Intl.DateTimeFormat('en-GB', {
      day: '2-digit',
      month: 'short',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }).formatToParts(new Date(ts * 1000));
    const byType = Object.fromEntries(parts.map((p) => [p.type, p.value]));
    return `${byType.day} ${byType.month} ${byType.year} ${byType.hour}:${byType.minute}`;
  };

  const formatDuration = (seconds: number) => {
    const safe = Math.max(0, Math.round(Number(seconds) || 0));
    const minutes = Math.floor(safe / 60);
    const secs = safe % 60;
    return minutes > 0 ? `${minutes}m ${secs}s` : `${secs}s`;
  };

  const perfTone = (fps: number) => {
    if (fps > 45) return {
      dot: 'bg-green-500',
      badge: 'bg-green-500/15 text-green-300 border-green-500',
    };
    if (fps >= 30) return {
      dot: 'bg-yellow-500',
      badge: 'bg-yellow-500/15 text-yellow-300 border-yellow-500',
    };
    return {
      dot: 'bg-red-500',
      badge: 'bg-red-500/15 text-red-300 border-red-500',
    };
  };

  const sceneCount = (value: any) => {
    if (Array.isArray(value)) return value.length;
    if (typeof value === 'string') return value.split(',').filter(Boolean).length || Number(value) || 0;
    return Number(value) || 0;
  };

  return (
    <div className="mx-auto w-full max-w-[640px] font-mono">
      <div className="sticky top-0 z-10 flex items-center justify-between border-4 border-black bg-black px-3 py-2 text-[0.625rem] font-black uppercase text-accent">
        <span>Historical Sessions</span>
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={() => setSortKey(sortKey === 'date' ? 'fps' : 'date')}
            className="text-accent"
            aria-label="Toggle sort field"
          >
            {sortKey === 'date' ? 'Date' : 'FPS'}
          </button>
          <button
            type="button"
            onClick={() => setSortDir(sortDir === 'desc' ? 'asc' : 'desc')}
            className="flex items-center gap-1 text-accent"
            aria-label="Toggle sort order"
          >
            {sortDir === 'desc' ? <ChevronDown size={14} /> : <ChevronUp size={14} />}
          </button>
        </div>
      </div>

      {sessions.length === 0 ? (
        <div className="border-x-4 border-b-4 border-black bg-bg-primary/50 p-10 text-center text-xs italic text-text-muted">
          No historical sessions found
        </div>
      ) : (
        <div className="flex flex-col gap-2 border-x-4 border-b-4 border-black bg-bg-primary/40 p-2 sm:p-3">
          {sortedSessions.map((s, idx) => {
            const avgFps = Number(s.avg_fps) || 0;
            const tone = perfTone(avgFps);
            const scenesVisited = sceneCount(s.scenes_visited);
            return (
              <button
                key={`${s.session_id || 'session'}-${idx}`}
                type="button"
                onClick={() => onSelectSession(s)}
                className="flex w-full items-center gap-3 border-2 border-black bg-bg-card p-3 text-left shadow-[2px_2px_0px_0px_black] transition-colors hover:bg-accent/5 sm:p-4"
              >
                <span className={`h-4 w-4 shrink-0 rounded-full border-2 border-black ${tone.dot}`} />
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-xs font-black text-text-primary sm:text-sm">
                    {formatDate(Number(s.start_time) || 0)}
                  </span>
                  <span className="mt-1 block truncate text-[0.625rem] text-text-muted">
                    {formatDuration(Number(s.duration) || 0)} · {scenesVisited} scenes visited
                  </span>
                </span>
                <span className={`shrink-0 border-2 px-2 py-1 text-[0.625rem] font-black ${tone.badge}`}>
                  {avgFps.toFixed(1)}
                </span>
                <ChevronRight size={18} className="shrink-0 text-text-muted" />
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
};
