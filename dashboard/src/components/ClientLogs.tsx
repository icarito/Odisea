import { useEffect, useState } from 'react';
import { getClientLogs } from '../api';

type ClientLog = {
  received_at: string;
  player_id: string;
  session_id: string;
  platform: string;
  version: string;
  gpu: string;
  lines: string[];
};

export function ClientLogs() {
  const [logs, setLogs] = useState<ClientLog[]>([]);
  const [error, setError] = useState(false);

  useEffect(() => {
    let alive = true;
    const load = async () => {
      try {
        const records = await getClientLogs();
        if (alive) {
          setLogs(Array.isArray(records) ? records : []);
          setError(false);
        }
      } catch {
        if (alive) setError(true);
      }
    };
    load();
    const timer = setInterval(load, 15000);
    return () => { alive = false; clearInterval(timer); };
  }, []);

  if (error) return <div className="py-4 text-center text-xs text-text-muted">No se pudieron cargar los errores.</div>;
  if (!logs.length) return <div className="py-4 text-center text-xs text-text-muted">Sin reportes de cliente.</div>;

  return <div className="flex h-full flex-col gap-2 overflow-y-auto">
    {logs.map((log, index) => (
      <article key={`${log.received_at}-${index}`} className="border border-border-custom bg-bg-card p-2 text-xs">
        <header className="text-text-muted">
          {new Date(log.received_at).toLocaleString()} · {log.platform} · {log.version} · {log.player_id.slice(0, 12)}
        </header>
        <div className="truncate text-[0.625rem] text-text-muted">{log.gpu}</div>
        <pre className="mt-1 whitespace-pre-wrap break-words font-mono text-[0.6875rem] text-warning">{log.lines.join('\n')}</pre>
      </article>
    ))}
  </div>;
}
