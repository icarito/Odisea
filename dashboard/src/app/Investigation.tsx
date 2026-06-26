import { useMemo } from 'react';
import { Link, useParams } from 'react-router-dom';
import {
  CartesianGrid,
  Line,
  LineChart,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { useIncidentQuery, useIncidentSamplesQuery, useUpdateIncidentStatus } from '../data/queries';
import type { IncidentStatus, SessionSample } from '../types';

const STATUS_META: Record<IncidentStatus, { label: string; cls: string }> = {
  open: { label: 'OPEN', cls: 'bg-danger text-black' },
  known: { label: 'KNOWN', cls: 'bg-warning text-black' },
  resolved: { label: 'RESOLVED', cls: 'bg-success text-black' },
  dismissed: { label: 'DISMISSED', cls: 'bg-text-muted text-black' },
};
const TYPE_LABELS: Record<string, string> = { low_fps: 'Low FPS', hotzone: 'Hotzone' };

function fmtWhen(ts: number): string {
  return ts ? new Date(ts * 1000).toLocaleString() : '—';
}

// Trayectoria 2D del jugador (plano X/Z) normalizada al bounding box de las
// muestras. Sin floorplan del server todavía — eso llega cuando portemos la
// proyección de escena (FloorplanProjection).
function Trajectory({ samples }: { samples: SessionSample[] }) {
  const W = 100;
  const H = 100;
  const pts = useMemo(() => {
    const valid = samples.filter((s) => Number.isFinite(s.pos_x) && Number.isFinite(s.pos_z));
    if (valid.length < 2) return null;
    const xs = valid.map((s) => s.pos_x);
    const zs = valid.map((s) => s.pos_z);
    const minX = Math.min(...xs), maxX = Math.max(...xs);
    const minZ = Math.min(...zs), maxZ = Math.max(...zs);
    const spanX = maxX - minX || 1;
    const spanZ = maxZ - minZ || 1;
    const pad = 6;
    const map = (s: SessionSample) => ({
      x: pad + ((s.pos_x - minX) / spanX) * (W - pad * 2),
      y: pad + ((s.pos_z - minZ) / spanZ) * (H - pad * 2),
    });
    const mapped = valid.map(map);
    return {
      line: mapped.map((p) => `${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(' '),
      start: mapped[0],
      end: mapped[mapped.length - 1],
    };
  }, [samples]);

  if (!pts) {
    return (
      <div className="flex h-full items-center justify-center text-[0.625rem] italic text-text-muted">
        Sin coordenadas de trayectoria
      </div>
    );
  }
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="h-full w-full" preserveAspectRatio="xMidYMid meet">
      <rect x={0} y={0} width={W} height={H} fill="#0c0e12" stroke="#232833" />
      <polyline points={pts.line} fill="none" stroke="#7fd1ff" strokeWidth={1} strokeLinejoin="round" />
      <circle cx={pts.start.x} cy={pts.start.y} r={2} fill="#3fb950" />
      <circle cx={pts.end.x} cy={pts.end.y} r={2.5} fill="#f85149" />
    </svg>
  );
}

// recharts tipa `content` de forma estricta; el resto del proyecto usa `any`
// para los tooltips custom — seguimos esa convención.
function fpsTooltip({ active, payload }: any) {
  if (!active || !payload?.length) return null;
  const d = payload[0].payload as { t: number; fps: number };
  return (
    <div className="border-2 border-black bg-bg-primary px-2 py-1 text-[0.5625rem] font-mono shadow-[2px_2px_0px_0px_black]">
      <div className="font-black text-accent">{new Date(d.t * 1000).toLocaleTimeString()}</div>
      <div>FPS: {d.fps.toFixed(1)}</div>
    </div>
  );
}

export function Investigation() {
  const { id = '' } = useParams();
  const incidentQ = useIncidentQuery(id);
  const samplesQ = useIncidentSamplesQuery(id);
  const update = useUpdateIncidentStatus();

  const incident = incidentQ.data ?? null;
  const samples = (samplesQ.data as SessionSample[]) ?? [];
  const loading = incidentQ.isLoading || samplesQ.isLoading;
  const err = incidentQ.error || samplesQ.error;
  const error = err instanceof Error ? err.message : err ? 'Error cargando el incidente' : null;

  const fpsSeries = useMemo(
    () =>
      samples
        .filter((s) => Number.isFinite(s.timestamp))
        .map((s) => ({ t: s.timestamp, fps: Number(s.fps) || 0 })),
    [samples],
  );

  const changeStatus = (status: IncidentStatus) => {
    if (!incident) return;
    update.mutate({ id: incident.id, status });
  };

  return (
    <div className="flex flex-col gap-4 p-4">
      <Link to="/investigate" className="text-[0.625rem] font-black uppercase tracking-widest text-text-muted hover:text-accent">
        ‹ Investigate
      </Link>

      {error && (
        <div className="border-2 border-danger bg-danger/10 px-3 py-2 text-[0.625rem] font-black uppercase text-danger">
          {error}
        </div>
      )}

      {loading ? (
        <div className="py-12 text-center text-[0.625rem] font-black uppercase tracking-widest text-text-muted">
          Cargando…
        </div>
      ) : !incident ? (
        <div className="py-12 text-center text-[0.625rem] font-black uppercase tracking-widest text-text-muted">
          Incidente no encontrado
        </div>
      ) : (
        <>
          <div className="border-2 border-black bg-bg-card p-3 shadow-[2px_2px_0px_0px_black]">
            <div className="flex flex-wrap items-center gap-2">
              <span className={`px-1.5 py-0.5 text-[0.5rem] font-black uppercase ${STATUS_META[incident.status]?.cls ?? ''}`}>
                {STATUS_META[incident.status]?.label ?? incident.status}
              </span>
              <span className="text-[0.625rem] font-black uppercase text-text-muted">
                {TYPE_LABELS[incident.type] ?? incident.type}
              </span>
              <span className="ml-auto text-sm font-black text-accent">{incident.count}×</span>
            </div>
            <div className="mt-2 text-sm font-black text-text-primary">
              {incident.scene}
              {incident.zone ? <span className="text-text-muted"> / {incident.zone}</span> : null}
            </div>
            <div className="mt-1 grid grid-cols-2 gap-x-4 gap-y-1 text-[0.625rem] text-text-muted sm:grid-cols-4">
              <div>Primero: {fmtWhen(incident.first_seen)}</div>
              <div>Último: {fmtWhen(incident.last_seen)}</div>
              <div>Muestras: {samples.length}</div>
              <div>Builds: {incident.builds_seen?.slice(-3).join(', ') || '—'}</div>
            </div>
            <div className="mt-3 flex flex-wrap gap-1">
              {(['known', 'resolved', 'dismissed', 'open'] as IncidentStatus[])
                .filter((s) => s !== incident.status)
                .map((s) => (
                  <button
                    key={s}
                    type="button"
                    onClick={() => changeStatus(s)}
                    className="border-2 border-black bg-bg-primary px-2 py-0.5 text-[0.5625rem] font-black uppercase text-text-muted hover:bg-accent hover:text-black"
                  >
                    {STATUS_META[s].label}
                  </button>
                ))}
            </div>
          </div>

          <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
            <div className="border-2 border-black bg-bg-card p-3 shadow-[2px_2px_0px_0px_black]">
              <div className="mb-2 text-[0.625rem] font-black uppercase tracking-widest text-accent">FPS</div>
              <div className="h-56">
                {fpsSeries.length > 1 ? (
                  <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={0}>
                    <LineChart data={fpsSeries} margin={{ top: 4, right: 8, bottom: 0, left: -12 }}>
                      <CartesianGrid strokeDasharray="3 3" stroke="#232833" />
                      <XAxis
                        dataKey="t"
                        type="number"
                        domain={['dataMin', 'dataMax']}
                        stroke="#666"
                        fontSize={9}
                        tickFormatter={(v) => new Date(Number(v) * 1000).toLocaleTimeString().slice(0, 5)}
                      />
                      <YAxis stroke="#666" fontSize={9} domain={[0, 'auto']} width={28} />
                      <Tooltip content={fpsTooltip} />
                      <ReferenceLine y={30} stroke="#f85149" strokeDasharray="3 3" />
                      <Line type="monotone" dataKey="fps" stroke="#7fd1ff" dot={false} strokeWidth={1.5} isAnimationActive={false} />
                    </LineChart>
                  </ResponsiveContainer>
                ) : (
                  <div className="flex h-full items-center justify-center text-[0.625rem] italic text-text-muted">
                    Sin serie de FPS
                  </div>
                )}
              </div>
            </div>

            <div className="border-2 border-black bg-bg-card p-3 shadow-[2px_2px_0px_0px_black]">
              <div className="mb-2 text-[0.625rem] font-black uppercase tracking-widest text-accent">Trayectoria (X/Z)</div>
              <div className="h-56">
                <Trajectory samples={samples} />
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
