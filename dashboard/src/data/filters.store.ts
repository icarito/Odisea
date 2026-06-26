import { create } from 'zustand';
import { persist } from 'zustand/middleware';

// Filtros globales del dashboard — el "pegamento" que el clásico tenía y la
// versión nueva había perdido. Un solo estado, persistido, que alimenta a todas
// las vistas. Cada vista aplica el subconjunto que le corresponde (la escena
// cruza Incidentes/Heatmap; el país, el Globo; plataforma/duración, Sesiones).
export interface GlobalFilters {
  scene: string; // '' = todas
  country: string; // código ISO-2, '' = todos
  platform: string; // '' = todas
  minDurationSec: number; // 0 = sin mínimo
  windowMs: number; // 0 = todo el tiempo
}

export const DEFAULT_FILTERS: GlobalFilters = {
  scene: '',
  country: '',
  platform: '',
  minDurationSec: 0,
  windowMs: 0,
};

interface FilterState extends GlobalFilters {
  setFilter: <K extends keyof GlobalFilters>(key: K, value: GlobalFilters[K]) => void;
  reset: () => void;
}

export const useFilters = create<FilterState>()(
  persist(
    (set) => ({
      ...DEFAULT_FILTERS,
      setFilter: (key, value) => set({ [key]: value } as Partial<FilterState>),
      reset: () => set({ ...DEFAULT_FILTERS }),
    }),
    { name: 'odisea-global-filters' },
  ),
);
