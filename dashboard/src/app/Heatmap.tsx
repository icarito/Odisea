import { Suspense, lazy, useEffect, useState } from 'react';
import { getHeatmap, getScenes } from '../api';

// El componente 3D pesado (three/fiber/drei) se carga lazy para no inflar el
// bundle inicial — igual que en el dashboard clásico.
const Heatmap3D = lazy(() => import('../components/Heatmap3D').then((m) => ({ default: m.Heatmap3D })));

const RESOLUTIONS = [3, 5, 8];

export function Heatmap() {
  const [scenes, setScenes] = useState<string[]>([]);
  const [scene, setScene] = useState('');
  const [resolution, setResolution] = useState(5);
  const [data, setData] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    getScenes()
      .then((s) => {
        const list = Array.isArray(s) ? s : [];
        setScenes(list);
        setScene((cur) => cur || list[0] || '');
      })
      .catch(() => {});
  }, []);

  useEffect(() => {
    if (!scene) return;
    let cancelled = false;
    setLoading(true);
    getHeatmap(scene, resolution)
      .then((d) => {
        if (!cancelled) setData(Array.isArray(d) ? d : []);
      })
      .catch(() => {
        if (!cancelled) setData([]);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [scene, resolution]);

  return (
    <div className="flex h-full flex-col gap-2 p-3">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-[0.625rem] font-black uppercase tracking-widest text-accent">Heatmap</span>
        <select
          value={scene}
          onChange={(e) => setScene(e.target.value)}
          className="border-2 border-black bg-bg-primary px-2 py-1 text-[0.625rem] font-mono text-text-primary"
        >
          {scenes.length === 0 && <option value="">(sin escenas)</option>}
          {scenes.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </select>
        <div className="flex items-center gap-1">
          {RESOLUTIONS.map((r) => (
            <button
              key={r}
              type="button"
              onClick={() => setResolution(r)}
              className={`border-2 border-black px-2 py-0.5 text-[0.5625rem] font-black uppercase ${
                resolution === r ? 'bg-accent text-black' : 'bg-bg-primary text-text-muted hover:text-accent'
              }`}
            >
              {r}
            </button>
          ))}
        </div>
        {loading && <span className="text-[0.5625rem] uppercase text-text-muted">cargando…</span>}
        <span className="ml-auto text-[0.5625rem] uppercase text-text-muted">{data.length} celdas</span>
      </div>
      <div className="min-h-0 flex-1 border-2 border-black bg-bg-card">
        <Suspense
          fallback={
            <div className="flex h-full items-center justify-center text-[0.625rem] font-black uppercase tracking-widest text-text-muted">
              Cargando heatmap…
            </div>
          }
        >
          <Heatmap3D data={data} resolution={resolution} scene={scene} />
        </Suspense>
      </div>
    </div>
  );
}
