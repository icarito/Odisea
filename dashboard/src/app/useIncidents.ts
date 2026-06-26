import { useCallback, useEffect, useRef, useState } from 'react';
import { getIncidents, setIncidentStatus } from '../api';
import { idbGet, idbSet } from '../lib/idbCache';
import type { IncidentGroup, IncidentStatus } from '../types';

export type IncidentFilter = IncidentStatus | 'all';

const cacheKey = (f: IncidentFilter) => `incidents:${f}`;

export interface UseIncidents {
  incidents: IncidentGroup[];
  /** true sólo hasta la primera pintura (cache o red); el cache la baja al instante */
  loading: boolean;
  /** revalidación en curso contra el server (con datos ya pintados) */
  refreshing: boolean;
  error: string | null;
  /** savedAt (ms) si lo que se ve viene del cache y aún no llegó la red; null si es fresco */
  fromCacheAt: number | null;
  refresh: () => void;
  changeStatus: (id: string, status: IncidentStatus) => Promise<void>;
}

/**
 * Lista de incidentes con stale-while-revalidate sobre IndexedDB: pinta el último
 * payload bueno al instante y revalida contra /incidents en segundo plano. Cachea
 * por filtro. Toda la lógica de datos vive acá para que la pantalla sea tonta y
 * testeable.
 */
export function useIncidents(filter: IncidentFilter): UseIncidents {
  const [incidents, setIncidents] = useState<IncidentGroup[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [fromCacheAt, setFromCacheAt] = useState<number | null>(null);
  // Descarta respuestas viejas si el filtro cambió mientras una fetch estaba en vuelo.
  const reqId = useRef(0);

  const fetchFresh = useCallback(async (f: IncidentFilter) => {
    const myReq = ++reqId.current;
    setRefreshing(true);
    setError(null);
    try {
      const data = await getIncidents(f === 'all' ? {} : { status: f });
      if (reqId.current !== myReq) return;
      setIncidents(data);
      setFromCacheAt(null);
      void idbSet(cacheKey(f), data);
    } catch (e) {
      if (reqId.current !== myReq) return;
      setError(e instanceof Error ? e.message : 'Error cargando incidentes');
    } finally {
      if (reqId.current === myReq) {
        setRefreshing(false);
        setLoading(false);
      }
    }
  }, []);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    idbGet<IncidentGroup[]>(cacheKey(filter)).then((entry) => {
      if (cancelled || !entry?.value) return;
      setIncidents(entry.value);
      setFromCacheAt(entry.savedAt);
      setLoading(false); // ya hay algo pintado mientras revalida
    });
    fetchFresh(filter);
    return () => {
      cancelled = true;
    };
  }, [filter, fetchFresh]);

  const refresh = useCallback(() => fetchFresh(filter), [filter, fetchFresh]);

  const changeStatus = useCallback(
    async (id: string, status: IncidentStatus) => {
      // Optimista + persistir el cache para que el cambio sobreviva un reload.
      setIncidents((prev) => {
        const next = prev
          .map((i) => (i.id === id ? { ...i, status } : i))
          .filter((i) => filter === 'all' || i.status === filter);
        void idbSet(cacheKey(filter), next);
        return next;
      });
      try {
        await setIncidentStatus(id, status);
      } catch {
        fetchFresh(filter); // revertir desde el server si falló
      }
    },
    [filter, fetchFresh],
  );

  return { incidents, loading, refreshing, error, fromCacheAt, refresh, changeStatus };
}
