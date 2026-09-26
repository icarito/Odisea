import React, { useEffect, useState } from 'react';
import { getLoadTimes } from '../api';
import type { LoadTimeStat, LoadTimesResponse } from '../types';
import { RetroCard } from './retro';

const DAYS = 7;

const fmtMs = (v: number | null | undefined): string =>
  typeof v === 'number' && Number.isFinite(v) ? `${Math.round(v)} ms` : '—';

const LoadRow: React.FC<{ label: string; stat: Pick<LoadTimeStat, 'n' | 'p50' | 'p90'>; accent?: boolean }> = ({ label, stat, accent }) => (
  <div className="flex items-center border-b border-black/10 px-2 py-1 text-[0.625rem] font-mono last:border-b-0">
    <span className={`min-w-0 flex-1 truncate ${accent ? 'font-black uppercase text-accent' : 'text-text-primary'}`}>{label}</span>
    <span className="w-10 shrink-0 text-right tabular-nums text-text-muted">{stat.n}</span>
    <span className="w-16 shrink-0 text-right tabular-nums">{fmtMs(stat.p50)}</span>
    <span className="w-16 shrink-0 text-right tabular-nums text-text-muted">{fmtMs(stat.p90)}</span>
  </div>
);

// Tiempos de carga agregados por escena destino + arranque, desde
// /ghosts/load_times. Sin props obligatorias: se monta y consulta solo.
export const LoadTimesPanel: React.FC = () => {
  const [data, setData] = useState<LoadTimesResponse | null>(null);
  const [error, setError] = useState(false);

  useEffect(() => {
    let alive = true;
    getLoadTimes(DAYS)
      .then((res) => { if (alive) { setData(res); setError(false); } })
      .catch(() => { if (alive) setError(true); });
    return () => { alive = false; };
  }, []);

  return (
    <RetroCard title={`Carga por escena (${DAYS}d)`}>
      <div className="flex items-center border-b-2 border-black px-2 pb-1 text-[0.5rem] font-black uppercase tracking-widest text-text-muted">
        <span className="min-w-0 flex-1">Escena</span>
        <span className="w-10 shrink-0 text-right">n</span>
        <span className="w-16 shrink-0 text-right">p50</span>
        <span className="w-16 shrink-0 text-right">p90</span>
      </div>
      {error ? (
        <div className="py-4 text-center text-[0.625rem] uppercase tracking-widest text-text-muted italic">Sin datos</div>
      ) : !data ? (
        <div className="py-4 text-center text-[0.625rem] uppercase tracking-widest text-text-muted/60 italic">Cargando…</div>
      ) : (
        <div>
          {data.scenes.map((s) => <LoadRow key={s.scene} label={s.scene} stat={s} />)}
          <LoadRow label="Arranque" stat={data.boot} accent />
          {data.scenes.length === 0 && data.boot.n === 0 && (
            <div className="py-4 text-center text-[0.625rem] uppercase tracking-widest text-text-muted italic">Sin muestras</div>
          )}
        </div>
      )}
    </RetroCard>
  );
};

export default LoadTimesPanel;
