import { useMemo } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  getGeoPlayers,
  getGhostData,
  getGhosts,
  getHeatmap,
  getHistoricalSessions,
  getIncident,
  getIncidentSamples,
  getIncidents,
  getScenes,
  setIncidentStatus,
} from '../api';
import type { GeoPlayer, IncidentGroup, IncidentStatus } from '../types';
import { useFilters } from './filters.store';
import {
  applyIncidentStatusToList,
  enrichSessionsWithGeo,
  filterGeoPlayers,
  filterSessions,
  geoByPlayer,
  normalizeGhostSample,
} from './selectors';

export type IncidentFilter = IncidentStatus | 'all';

// --- Queries crudas (pipeline) ----------------------------------------------

export function useScenesQuery() {
  return useQuery({ queryKey: ['scenes'], queryFn: getScenes });
}

export function useGeoPlayersQuery() {
  return useQuery({
    queryKey: ['geoPlayers'],
    queryFn: getGeoPlayers,
    refetchInterval: 15_000, // ubicaciones en vivo
  });
}

export function useHeatmapQuery(scene: string, resolution: number) {
  return useQuery({
    queryKey: ['heatmap', scene, resolution],
    queryFn: () => getHeatmap(scene, resolution),
    enabled: !!scene,
  });
}

export function useGhostsQuery(scene: string) {
  return useQuery({
    queryKey: ['ghosts', scene],
    queryFn: () => getGhosts(scene),
    enabled: !!scene,
  });
}

export function useHistoricalSessionsQuery() {
  return useQuery({
    queryKey: ['historicalSessions'],
    queryFn: getHistoricalSessions,
    refetchInterval: 30_000,
  });
}

// Muestras de una sesión para reproducción (ghosts), normalizadas al heartbeat
// plano que espera SessionPlayback. enabled sólo cuando hay sesión elegida.
export function useGhostDataQuery(playerId: string | undefined, sessionId: string | undefined) {
  return useQuery({
    queryKey: ['ghostData', playerId, sessionId],
    queryFn: () => getGhostData(playerId as string, sessionId as string),
    enabled: !!playerId && !!sessionId,
    select: (rows: unknown) => {
      const arr = Array.isArray(rows)
        ? rows
        : typeof rows === 'string'
          ? rows.split('\n').filter((l) => l.trim()).map((l) => JSON.parse(l))
          : [];
      return arr.map(normalizeGhostSample);
    },
  });
}

export function useIncidentQuery(id: string) {
  return useQuery({ queryKey: ['incident', id], queryFn: () => getIncident(id), enabled: !!id });
}

export function useIncidentSamplesQuery(id: string) {
  return useQuery({ queryKey: ['incidentSamples', id], queryFn: () => getIncidentSamples(id), enabled: !!id });
}

// --- Hooks filtrados (query + filtros globales) -----------------------------

// La escena es un filtro global; la mandamos como parámetro del server para no
// traer de más. El status viene de la UI de la pantalla (tabs del Inbox).
export function useFilteredIncidents(status: IncidentFilter) {
  const scene = useFilters((s) => s.scene);
  return useQuery({
    queryKey: ['incidents', status, scene],
    queryFn: () => getIncidents({ ...(status === 'all' ? {} : { status }), ...(scene ? { scene } : {}) }),
  });
}

export function useFilteredGeoPlayers() {
  const country = useFilters((s) => s.country);
  const windowMs = useFilters((s) => s.windowMs);
  const q = useGeoPlayersQuery();
  const data = useMemo(
    () => filterGeoPlayers((q.data as GeoPlayer[]) ?? [], { scene: '', country, platform: '', minDurationSec: 0, windowMs }),
    [q.data, country, windowMs],
  );
  return { ...q, data };
}

// Sesiones históricas + live, enriquecidas con geo y filtradas por los filtros
// globales (escena/país/plataforma/duración). Presentacional: la vista History
// sólo consume `data`.
export function useFilteredHistoricalSessions() {
  const scene = useFilters((s) => s.scene);
  const country = useFilters((s) => s.country);
  const platform = useFilters((s) => s.platform);
  const minDurationSec = useFilters((s) => s.minDurationSec);
  const sessionsQ = useHistoricalSessionsQuery();
  const geoQ = useGeoPlayersQuery();

  const data = useMemo(() => {
    const sessions = (sessionsQ.data as Array<Record<string, unknown>>) ?? [];
    const byPlayer = geoByPlayer((geoQ.data as GeoPlayer[]) ?? []);
    const enriched = enrichSessionsWithGeo(sessions, byPlayer);
    return filterSessions(enriched, { scene, country, platform, minDurationSec, windowMs: 0 }, byPlayer);
  }, [sessionsQ.data, geoQ.data, scene, country, platform, minDurationSec]);

  return { ...sessionsQ, data };
}

// --- Mutación: cambiar estado de incidente (optimista) ----------------------

export function useUpdateIncidentStatus() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, status }: { id: string; status: IncidentStatus }) => setIncidentStatus(id, status),
    onMutate: async ({ id, status }) => {
      await qc.cancelQueries({ queryKey: ['incidents'] });
      const snapshots = qc.getQueriesData<IncidentGroup[]>({ queryKey: ['incidents'] });
      // Para cada query ['incidents', status, scene]: actualizar el item y, si la
      // query está filtrada por un status distinto al nuevo, sacarlo de la lista.
      for (const [key, data] of snapshots) {
        if (!Array.isArray(data)) continue;
        const keyStatus = key[1] as IncidentFilter;
        qc.setQueryData(key, applyIncidentStatusToList(data, id, status, keyStatus));
      }
      // Detalle (vista Investigation) también optimista.
      const prevDetail = qc.getQueryData<IncidentGroup>(['incident', id]);
      if (prevDetail) qc.setQueryData(['incident', id], { ...prevDetail, status });
      return { snapshots, prevDetail };
    },
    onError: (_e, { id }, ctx) => {
      ctx?.snapshots?.forEach(([key, data]) => qc.setQueryData(key, data));
      if (ctx?.prevDetail) qc.setQueryData(['incident', id], ctx.prevDetail);
    },
    onSettled: (_data, _err, { id }) => {
      qc.invalidateQueries({ queryKey: ['incidents'] });
      qc.invalidateQueries({ queryKey: ['incident', id] });
    },
  });
}
