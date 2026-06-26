import { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { getIncidents, setIncidentStatus } from '../api';
import type { IncidentGroup, IncidentStatus } from '../types';

const STATUS_META: Record<IncidentStatus, { label: string; cls: string }> = {
  open: { label: 'OPEN', cls: 'bg-danger text-black' },
  known: { label: 'KNOWN', cls: 'bg-warning text-black' },
  resolved: { label: 'RESOLVED', cls: 'bg-success text-black' },
  dismissed: { label: 'DISMISSED', cls: 'bg-text-muted text-black' },
};

const TYPE_LABELS: Record<string, string> = {
  low_fps: 'Low FPS',
  hotzone: 'Hotzone',
};

const FILTERS: Array<IncidentStatus | 'all'> = ['open', 'known', 'resolved', 'dismissed', 'all'];

function fmtWhen(ts: number): string {
  if (!ts) return '—';
  return new Date(ts * 1000).toLocaleString();
}

function IncidentCard({
  item,
  onChange,
  onOpen,
}: {
  item: IncidentGroup;
  onChange: (id: string, status: IncidentStatus) => void;
  onOpen: (id: string) => void;
}) {
  const meta = STATUS_META[item.status] ?? STATUS_META.open;
  return (
    <div className="border-2 border-black bg-bg-card shadow-[2px_2px_0px_0px_black]">
      <button
        type="button"
        onClick={() => onOpen(item.id)}
        className="flex w-full items-start justify-between gap-3 px-3 py-2 text-left hover:bg-accent/5"
      >
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <span className={`px-1.5 py-0.5 text-[0.5rem] font-black uppercase ${meta.cls}`}>
              {meta.label}
            </span>
            <span className="text-[0.625rem] font-black uppercase text-text-muted">
              {TYPE_LABELS[item.type] ?? item.type}
            </span>
            <span className="ml-auto text-xs font-black text-accent">{item.count}×</span>
          </div>
          <div className="mt-1 truncate text-xs font-black text-text-primary">
            {item.scene}
            {item.zone ? <span className="text-text-muted"> / {item.zone}</span> : null}
          </div>
          <div className="mt-0.5 text-[0.625rem] text-text-muted">
            Último: {fmtWhen(item.last_seen)}
          </div>
          {item.builds_seen?.length ? (
            <div className="mt-0.5 truncate text-[0.5625rem] text-text-muted">
              Builds: {item.builds_seen.slice(-3).join(', ')}
            </div>
          ) : null}
        </div>
      </button>
      <div className="flex flex-wrap gap-1 border-t-2 border-black/30 px-3 py-1.5">
        {item.status !== 'known' && (
          <ActionBtn label="Known" tone="warning" onClick={() => onChange(item.id, 'known')} />
        )}
        {item.status !== 'resolved' && (
          <ActionBtn label="Resolver" tone="success" onClick={() => onChange(item.id, 'resolved')} />
        )}
        {item.status !== 'dismissed' && (
          <ActionBtn label="Descartar" tone="muted" onClick={() => onChange(item.id, 'dismissed')} />
        )}
        {item.status !== 'open' && (
          <ActionBtn label="Reabrir" tone="danger" onClick={() => onChange(item.id, 'open')} />
        )}
      </div>
    </div>
  );
}

const TONES: Record<string, string> = {
  warning: 'border-warning text-warning hover:bg-warning',
  success: 'border-success text-success hover:bg-success',
  danger: 'border-danger text-danger hover:bg-danger',
  muted: 'border-text-muted text-text-muted hover:bg-text-muted',
};

function ActionBtn({ label, tone, onClick }: { label: string; tone: string; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`border-2 px-2 py-0.5 text-[0.5625rem] font-black uppercase transition-colors hover:text-black ${TONES[tone]}`}
    >
      {label}
    </button>
  );
}

export function Inbox() {
  const navigate = useNavigate();
  const [filter, setFilter] = useState<IncidentStatus | 'all'>('open');
  const [incidents, setIncidents] = useState<IncidentGroup[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async (f: IncidentStatus | 'all') => {
    setLoading(true);
    setError(null);
    try {
      const data = await getIncidents(f === 'all' ? {} : { status: f });
      setIncidents(data);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Error cargando incidentes');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load(filter);
  }, [filter, load]);

  const handleChange = useCallback(
    async (id: string, status: IncidentStatus) => {
      // Optimista: sacar de la lista si ya no matchea el filtro activo.
      setIncidents((prev) =>
        prev.map((i) => (i.id === id ? { ...i, status } : i)).filter((i) => filter === 'all' || i.status === filter),
      );
      try {
        await setIncidentStatus(id, status);
      } catch {
        load(filter); // revertir desde el server si falló
      }
    },
    [filter, load],
  );

  return (
    <div className="flex flex-col gap-3 p-4">
      <div className="flex flex-wrap items-center gap-2">
        <h2 className="mr-2 text-xs font-black uppercase tracking-widest text-accent">Inbox de incidentes</h2>
        {FILTERS.map((f) => (
          <button
            key={f}
            type="button"
            onClick={() => setFilter(f)}
            className={`border-2 border-black px-2 py-0.5 text-[0.5625rem] font-black uppercase transition-colors ${
              filter === f ? 'bg-accent text-black' : 'bg-bg-primary text-text-muted hover:text-accent'
            }`}
          >
            {f}
          </button>
        ))}
        <button
          type="button"
          onClick={() => load(filter)}
          className="ml-auto border-2 border-black bg-bg-primary px-2 py-0.5 text-[0.5625rem] font-black uppercase text-text-muted hover:bg-accent hover:text-black"
        >
          Recargar
        </button>
      </div>

      {error && (
        <div className="border-2 border-danger bg-danger/10 px-3 py-2 text-[0.625rem] font-black uppercase text-danger">
          {error}
        </div>
      )}

      {loading ? (
        <div className="py-12 text-center text-[0.625rem] font-black uppercase tracking-widest text-text-muted">
          Cargando…
        </div>
      ) : incidents.length === 0 ? (
        <div className="py-12 text-center text-[0.625rem] font-black uppercase tracking-widest text-text-muted">
          Sin incidentes {filter !== 'all' ? `(${filter})` : ''}
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 xl:grid-cols-3">
          {incidents.map((item) => (
            <IncidentCard key={item.id} item={item} onChange={handleChange} onOpen={(id) => navigate(`/investigation/${id}`)} />
          ))}
        </div>
      )}
    </div>
  );
}
