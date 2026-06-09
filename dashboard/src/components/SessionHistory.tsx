import React, { useEffect, useState } from 'react';
import { apiFetch } from '../api';

import { SessionTimeline } from './SessionTimeline';

interface HistorySession {
  player_id: string;
  session_id: string;
  timestamp: number;
  size_kb: number;
}

interface SessionDetail {
    events: { scene: string, zone: string, mode: string, timestamp: number }[];
    stats: {
        avgFps: number;
        peakMem: number;
        duration: number;
    }
}

export const SessionHistory: React.FC = () => {
  const [sessions, setSessions] = useState<HistorySession[]>([]);
  const [loading, setLoading] = useState(false);
  const [selectedSession, setSelectedSession] = useState<HistorySession | null>(null);
  const [detail, setDetail] = useState<SessionDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);

  useEffect(() => {
    const fetchSessions = async () => {
      setLoading(true);
      try {
        const response = await apiFetch("/sessions/history");
        const data = await response.json();
        setSessions(data);
      } catch (e) {
        console.error("Failed to fetch sessions history", e);
      } finally {
        setLoading(false);
      }
    };
    fetchSessions();
  }, []);

  const viewSession = async (session: HistorySession) => {
    setSelectedSession(session);
    setDetailLoading(true);
    setDetail(null);
    try {
        const token = sessionStorage.getItem("odisea_token");
        const response = await fetch(`/sessions/${session.player_id}/${session.session_id}`, {
            headers: { "Authorization": `Bearer ${token}` }
        });
        if (!response.ok) throw new Error("Fetch failed");

        const text = await response.text();
        const lines = text.split("\n").filter(l => l.trim());
        const data = lines.map(l => JSON.parse(l));

        if (data.length > 0) {
            const events: any[] = [];
            let totalFps = 0;
            let peakMem = 0;

            data.forEach((hb: any) => {
                const lastEvent = events[events.length - 1];
                if (!lastEvent ||
                    lastEvent.scene !== hb.player.scene ||
                    lastEvent.zone !== hb.player.zone ||
                    lastEvent.mode !== hb.player.mode) {
                    events.push({
                        scene: hb.player.scene,
                        zone: hb.player.zone,
                        mode: hb.player.mode,
                        timestamp: hb.timestamp
                    });
                }
                totalFps += hb.player.fps;
                if (hb.player.memory_mb > peakMem) peakMem = hb.player.memory_mb;
            });

            const duration = data[data.length-1].timestamp - data[0].timestamp;

            setDetail({
                events,
                stats: {
                    avgFps: Math.round(totalFps / data.length),
                    peakMem: Math.round(peakMem),
                    duration: Math.round(duration)
                }
            });
        }
    } catch (e) {
        console.error("Failed to load session detail", e);
    } finally {
        setDetailLoading(false);
    }
  };

  const downloadSession = async (pid: string, sid: string) => {
    try {
        const token = sessionStorage.getItem("odisea_token");
        const response = await fetch(`/sessions/${pid}/${sid}`, {
            headers: { "Authorization": `Bearer ${token}` }
        });
        if (!response.ok) throw new Error("Download failed");

        const blob = await response.blob();
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `${sid}.jsonl`;
        document.body.appendChild(a);
        a.click();
        a.remove();
    } catch (e) {
        alert("Failed to download session file");
    }
  };

  return (
    <div className="flex flex-col gap-2 p-2">
      {selectedSession && (
          <div className="mb-4 p-3 border border-accent bg-bg-card rounded text-[10px] flex flex-col gap-2">
              <div className="flex justify-between items-center">
                  <span className="text-accent font-bold">DETALLE DE SESIÓN</span>
                  <button onClick={() => setSelectedSession(null)} className="text-text-muted hover:text-white">✕</button>
              </div>
              <div className="text-text-muted truncate">{selectedSession.session_id}</div>

              {detailLoading && <div>Procesando datos...</div>}

              {detail && (
                  <>
                    <div className="grid grid-cols-3 gap-2 text-center border-y border-border-custom py-2 my-1">
                        <div>
                            <div className="text-text-muted">DURACIÓN</div>
                            <div className="text-text-primary">{detail.stats.duration}s</div>
                        </div>
                        <div>
                            <div className="text-text-muted">AVG FPS</div>
                            <div className="text-text-primary">{detail.stats.avgFps}</div>
                        </div>
                        <div>
                            <div className="text-text-muted">PEAK MEM</div>
                            <div className="text-text-primary">{detail.stats.peakMem}MB</div>
                        </div>
                    </div>
                    <div className="flex flex-col gap-1">
                        <span className="text-text-muted uppercase font-bold">Timeline</span>
                        <SessionTimeline events={detail.events} />
                    </div>
                    <button
                        onClick={() => downloadSession(selectedSession.player_id, selectedSession.session_id)}
                        className="mt-2 w-full py-1.5 bg-accent text-bg-primary font-bold rounded hover:opacity-90"
                    >
                        DESCARGAR JSONL
                    </button>
                  </>
              )}
          </div>
      )}

      {loading && <div className="text-xs text-text-muted">Cargando sesiones...</div>}
      {!selectedSession && sessions.length === 0 && !loading && <div className="text-xs text-text-muted text-center py-4">Sin sesiones históricas</div>}

      {!selectedSession && sessions.map(s => (
        <div
            key={s.session_id}
            onClick={() => viewSession(s)}
            className="p-2 border border-border-custom bg-bg-card rounded text-[10px] group cursor-pointer hover:border-accent transition-colors"
        >
          <div className="flex justify-between items-center mb-1">
            <span className="text-accent font-bold">{s.player_id.slice(0, 8)}</span>
            <span className="text-text-muted">{new Date(s.timestamp * 1000).toLocaleDateString()}</span>
          </div>
          <div className="text-text-muted truncate mb-2">{s.session_id}</div>
          <div className="flex justify-between items-center">
            <span className="text-text-muted">{s.size_kb} KB</span>
            <span className="text-accent opacity-0 group-hover:opacity-100 transition-opacity">VER DETALLE →</span>
          </div>
        </div>
      ))}
    </div>
  );
};
