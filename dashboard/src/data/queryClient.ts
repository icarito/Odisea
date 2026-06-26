import { QueryClient } from '@tanstack/react-query';
import { createAsyncStoragePersister } from '@tanstack/query-async-storage-persister';
import { idbGet, idbSet } from '../lib/idbCache';

// Pipeline de server-state central. react-query maneja cache, SWR, dedup y
// refetch; lo persistimos en IndexedDB (reusando idbCache) para que al reabrir
// el dashboard pinte el último estado al instante en vez de quedar lento.
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000, // 30s "fresco": navegar entre vistas no re-fetchea
      gcTime: 24 * 60 * 60 * 1000, // retener para hidratar al reabrir
      refetchOnWindowFocus: true,
      retry: 1,
    },
  },
});

// Adaptador de storage async sobre idbCache (el persister guarda un único blob).
const storage = {
  getItem: async (key: string) => {
    const entry = await idbGet<string>(key);
    return entry?.value ?? null;
  },
  setItem: async (key: string, value: string) => {
    await idbSet(key, value);
  },
  removeItem: async (key: string) => {
    await idbSet(key, '');
  },
};

export const persister = createAsyncStoragePersister({
  storage,
  key: 'odisea-rq-cache',
  throttleTime: 1000,
});
