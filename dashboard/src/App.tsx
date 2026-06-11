import { useState, useEffect } from 'react';
import { Toaster, toast } from 'react-hot-toast';
import { LoginScreen } from './components/LoginScreen';
import { Viewport3D } from './components/Viewport3D';
import { Heatmap3D } from './components/Heatmap3D';
import { LiveMap } from './components/LiveMap';
import { HistoricalTable } from './components/HistoricalTable';
import { SessionPlayback } from './components/SessionPlayback';
import { DashboardLayout } from './components/DashboardLayout';
import { PlayerBottomSheet } from './components/PlayerBottomSheet';
import { RetroCard, RetroButton, RetroSelect, RetroInput } from './components/retro';
import { useTelemetry } from './hooks/useTelemetry';
import { useWebSocket } from './hooks/useWebSocket';
import { useLayoutPersistence } from './hooks/useLayoutPersistence';
import { getHeatmap, getHistoricalSessions, getGhostData, getScenes } from './api';
import { Maximize2, Play, X } from 'lucide-react';

type Tab = 'live' | 'heatmap' | 'history' | 'playback';

function Dashboard({ onLogout }: { onLogout: () => void }) {
  const { heartbeats, isConnected, alerts, history } = useTelemetry();
  const { lastMessage } = useWebSocket();
  const { layout, updateLayout } = useLayoutPersistence();
  
  const activeTab = layout.activeTab as Tab;
  const setActiveTab = (t: Tab) => updateLayout({ activeTab: t });

  const [selectedPlayerId, setSelectedPlayerId] = useState<string | null>(null);
  const [heatmapData, setHeatmapData] = useState<any[] | undefined>();
  const [showHeatmap, setShowHeatmap] = useState(false);
  const [showLiveGhosts, setShowLiveGhosts] = useState(true);

  // Live tab view toggle: 2D birdseye map vs 3D perspective.
  const [liveView, setLiveView] = useState<'birdseye' | '3d'>('3d');
  // CSS overlay fullscreen for the 3D canvas (NOT the browser Fullscreen API,
  // which is unreliable on mobile).
  const [fs3d, setFs3d] = useState(false);
  // Player list bottom sheet (opened from the header counter).
  const [showPlayerSheet, setShowPlayerSheet] = useState(false);

  // Heatmap State
  const [heatmapScene, setHeatmapScene] = useState('Dome_Crio');
  const [heatmapRes, setHeatmapRes] = useState(5);

  // Available scenes (fetched from backend, not hardcoded)
  const [scenes, setScenes] = useState<string[]>([]);

  // History State
  const [historicalSessions, setHistoricalSessions] = useState<any[]>([]);
  const [selectedSession, setSelectedSession] = useState<any>(null);
  const [playbackData, setPlaybackData] = useState<any[]>([]);

  // Live State
  const [liveGhosts, setLiveGhosts] = useState<any[]>([]);


  useEffect(() => {
    if (alerts.length > 0) {
        const latest = alerts[0];
        toast(latest.message, {
            icon: latest.type === 'disconnect' ? '❌' : '⚠️',
            style: {
                borderRadius: '0px',
                background: '#13161c',
                color: '#d7dbe0',
                border: '4px solid #000',
                fontSize: '12px',
                fontFamily: 'monospace',
                boxShadow: '4px 4px 0px 0px #000'
            },
        });
    }
  }, [alerts]);

  useEffect(() => {
    if (lastMessage?.type === 'alert') {
      toast(lastMessage.message, { icon: '🔥', duration: 4000 });
    }
  }, [lastMessage]);

  useEffect(() => {
    const active = Object.entries(heartbeats).map(([pid, hb]: [string, any]) => {
      const p = hb.player || {};
      const pos = p.position || [0,0,0];
      return {
        player_id: pid,
        session_id: hb.session_id,
        scene: p.scene,
        pos_x: pos[0],
        pos_y: pos[1],
        pos_z: pos[2],
        fps: p.fps,
        last_seen: hb.timestamp
      };
    });
    setLiveGhosts(active);
  }, [heartbeats]);

  useEffect(() => {
    if (activeTab === 'heatmap') {
      getHeatmap(heatmapScene, heatmapRes)
        .then((d) => setHeatmapData(Array.isArray(d) ? d : []))
        .catch(() => setHeatmapData([]));
    }
  }, [activeTab, heatmapScene, heatmapRes]);

  useEffect(() => {
    if (activeTab === 'history') {
      getHistoricalSessions()
        .then((d) => setHistoricalSessions(Array.isArray(d) ? d : []))
        .catch(() => setHistoricalSessions([]));
    }
  }, [activeTab]);

  useEffect(() => {
    getScenes()
      .then((d) => setScenes(Array.isArray(d) ? d : []))
      .catch(() => setScenes([]));
  }, []);

  // Normalizes a heartbeat to the flat shape the playback charts use.
  // /api/ghosts returns flat SQLite rows (hb.fps, hb.pos_x, ...), while the
  // runtime/JSONL format nests them under hb.player. Support both.
  const normalizeHeartbeat = (hb: any) => {
    const p = hb.player || {};
    const pos = p.position;
    return {
      timestamp: hb.timestamp ?? 0,
      fps: hb.fps ?? p.fps ?? 0,
      memory_mb: hb.memory_mb ?? p.memory_mb ?? 0,
      pos_x: hb.pos_x ?? pos?.[0] ?? 0,
      pos_y: hb.pos_y ?? pos?.[1] ?? 0,
      pos_z: hb.pos_z ?? pos?.[2] ?? 0,
      scene: hb.scene ?? p.scene ?? "?",
      platform: hb.platform ?? p.platform ?? "?",
      engine_version: hb.engine_version ?? hb.godot_version ?? p.engine_version ?? "?",
    };
  };

  const handleSelectHistorySession = async (session: any) => {
    setSelectedSession(session);
    setActiveTab('playback');
    try {
      const data = await getGhostData(session.player_id, session.session_id);
      let rows: any[] = [];
      if (Array.isArray(data)) {
        rows = data;
      } else if (typeof data === 'string') {
        rows = data.split('\n').filter(l => l.trim()).map(l => JSON.parse(l));
      }
      setPlaybackData(rows.map(normalizeHeartbeat));
    } catch (e) {
      toast.error("Failed to load session data");
      setPlaybackData([]);
    }
  };

  const [followPlayer, setFollowPlayer] = useState(true);
  const [wireframe, setWireframe] = useState(false);
  const [manualScene, setManualScene] = useState<string | null>(null);

  const pids = Object.keys(heartbeats);

  useEffect(() => {
    if (showHeatmap && manualScene) {
      getHeatmap(manualScene).then(setHeatmapData).catch(console.error);
    } else {
      setHeatmapData(undefined);
    }
  }, [showHeatmap, manualScene]);

  const activeId = selectedPlayerId || pids[0];
  const activeHb = heartbeats[activeId];
  const activeHistory = history[activeId];
  const staleAge = activeHb ? (activeHb.timestamp ? (Date.now() - activeHb.timestamp * 1000) / 1000 : 0) : 0;

  const safePos = (p: any): [number, number, number] => {
    if (Array.isArray(p) && p.length >= 3) {
      return [Number(p[0]), Number(p[1]), Number(p[2])];
    }
    return [0, 0, 0];
  };

  const liveGhostMarkers = showLiveGhosts
    ? Object.values(heartbeats).filter((h: any) => h.player_id !== activeId)
    : [];

  // The 3D viewport element, reused inline and inside the fullscreen overlay.
  const viewport3D = (
    <Viewport3D
      position={activeHb ? safePos(activeHb.player.position) : [0, 0, 0]}
      yaw={activeHb ? Number(activeHb.player.yaw) || 0 : 0}
      pitch={activeHb ? Number(activeHb.player.pitch) || 0 : 0}
      roll={activeHb ? Number(activeHb.player.roll) || 0 : 0}
      trail={activeHistory?.trail || []}
      follow={followPlayer}
      wireframe={wireframe}
      sceneName={manualScene || activeHb?.player.scene || ""}
      staleAge={staleAge}
      heatmapData={showHeatmap ? heatmapData : undefined}
      liveGhosts={liveGhostMarkers}
      hud={activeHb ? { fps: activeHb.player?.fps, scene: activeHb.player?.scene } : null}
    />
  );

  return (
    <DashboardLayout
      onLogout={onLogout}
      isConnected={isConnected}
      activeTab={activeTab}
      setActiveTab={setActiveTab}
      playerCount={pids.length}
      onPlayersClick={() => setShowPlayerSheet(true)}
      isSessionSelected={!!selectedSession}
    >
      <Toaster position="bottom-right" />

      <PlayerBottomSheet
        open={showPlayerSheet}
        onClose={() => setShowPlayerSheet(false)}
        players={Object.values(heartbeats)}
        activeId={activeId}
        onSelect={(pid) => setSelectedPlayerId(pid)}
      />

      {/* CSS fullscreen overlay for the 3D canvas (works on mobile). */}
      {fs3d && (
        <div className="fixed inset-0 z-[9999] bg-black flex flex-col">
          <button
            onClick={() => setFs3d(false)}
            className="absolute top-3 right-3 z-10 p-2 border-2 border-white/40 bg-black/60 text-white"
            aria-label="Close fullscreen"
          >
            <X size={24} />
          </button>
          <div className="flex-1 min-h-0">{viewport3D}</div>
        </div>
      )}
      
      {activeTab === 'live' && (
        <div className="flex flex-col h-full min-h-0">
          {/* Toolbar: view toggle (Birdseye / 3D) + view-specific controls */}
          <div className="shrink-0 flex flex-wrap items-center gap-2 p-2 border-b-2 border-black bg-bg-card/60">
            <div className="flex border-2 border-black">
              <button
                onClick={() => setLiveView('birdseye')}
                className={`px-3 py-1 text-[0.625rem] font-black uppercase ${liveView === 'birdseye' ? 'bg-accent text-black' : 'bg-bg-primary text-text-muted'}`}
              >
                Birdseye
              </button>
              <button
                onClick={() => setLiveView('3d')}
                className={`px-3 py-1 text-[0.625rem] font-black uppercase border-l-2 border-black ${liveView === '3d' ? 'bg-accent text-black' : 'bg-bg-primary text-text-muted'}`}
              >
                3D
              </button>
            </div>

            <RetroSelect
              value={manualScene || activeHb?.player.scene || ""}
              onChange={(e) => setManualScene(e.target.value)}
              className="py-1 px-2 text-[0.625rem] w-32"
            >
              <option value="">AUTO SCENE</option>
              {scenes.map(s => <option key={s} value={s}>{s}</option>)}
            </RetroSelect>

            {liveView === '3d' && (
              <div className="flex gap-1 flex-wrap">
                <RetroButton variant={followPlayer ? 'primary' : 'secondary'} onClick={() => setFollowPlayer(!followPlayer)} className="py-1 px-2 text-[0.625rem]">FOLLOW</RetroButton>
                <RetroButton variant={wireframe ? 'primary' : 'secondary'} onClick={() => setWireframe(!wireframe)} className="py-1 px-2 text-[0.625rem]">MESH</RetroButton>
                <RetroButton variant={showHeatmap ? 'primary' : 'secondary'} onClick={() => setShowHeatmap(!showHeatmap)} className="py-1 px-2 text-[0.625rem]">HEAT</RetroButton>
                <RetroButton variant={showLiveGhosts ? 'primary' : 'secondary'} onClick={() => setShowLiveGhosts(!showLiveGhosts)} className="py-1 px-2 text-[0.625rem]">PEERS</RetroButton>
                <RetroButton variant="secondary" onClick={() => setFs3d(true)} className="py-1 px-2" title="Fullscreen 3D"><Maximize2 size={14} /></RetroButton>
              </div>
            )}
          </div>

          {/* View area fills all remaining space (no fixed heights). */}
          <div className="flex-1 min-h-0 relative">
            {!activeHb ? (
              <div className="h-full flex items-center justify-center p-6 text-center text-text-muted italic text-sm">
                No active player. Tap the player counter above to pick one.
              </div>
            ) : liveView === '3d' ? (
              <div className="absolute inset-0">{viewport3D}</div>
            ) : (
              <LiveMap ghosts={liveGhosts} sceneName={manualScene || activeHb?.player.scene || ""} />
            )}
          </div>
        </div>
      )}

      {activeTab === 'heatmap' && (
        <div className="flex flex-col h-full p-4 gap-4 overflow-hidden">
          <RetroCard>
            <div className="flex flex-wrap gap-4 items-end">
              <div className="flex-1 min-w-[200px]">
                <RetroSelect
                  label="Scene Target"
                  value={heatmapScene}
                  onChange={(e) => setHeatmapScene(e.target.value)}
                >
                  {scenes.map(s => <option key={s} value={s}>{s}</option>)}
                </RetroSelect>
              </div>
              <div className="w-24">
                <RetroInput
                  label="Res (m)"
                  type="number"
                  value={heatmapRes.toString()}
                  onChange={(e) => setHeatmapRes(Number(e.target.value))}
                />
              </div>
              <div className="flex-1 flex justify-end gap-2 mb-2">
                 <div className="hidden sm:grid grid-cols-2 lg:grid-cols-4 gap-2 text-[0.5rem] uppercase font-bold">
                    <div className="flex items-center gap-1"><div className="w-2 h-2 bg-green-500" /> Low</div>
                    <div className="flex items-center gap-1"><div className="w-2 h-2 bg-yellow-500" /> Med</div>
                    <div className="flex items-center gap-1"><div className="w-2 h-2 bg-orange-500" /> High</div>
                    <div className="flex items-center gap-1"><div className="w-2 h-2 bg-red-500" /> Crit</div>
                 </div>
              </div>
            </div>
          </RetroCard>

          <div className="flex-1 min-h-0 relative border-4 border-black shadow-retro overflow-hidden">
            <Heatmap3D data={heatmapData ?? []} resolution={heatmapRes} />
          </div>
        </div>
      )}

      {activeTab === 'history' && (
        <div className="flex-1 p-4 sm:p-6 overflow-y-auto">
          <RetroCard title="HISTORICAL ARCHIVE">
             <HistoricalTable sessions={historicalSessions} onSelectSession={handleSelectHistorySession} />
          </RetroCard>
        </div>
      )}

      {activeTab === 'playback' && (
        <div className="flex-1 p-4 sm:p-6 overflow-y-auto flex flex-col gap-6">
          <div className="flex justify-between items-center bg-bg-card border-4 border-black p-4 shadow-retro">
            <div>
              <h2 className="text-sm font-black text-accent uppercase tracking-tighter flex items-center gap-2">
                <Play size={16} /> PLAYBACK MODULE
              </h2>
              <div className="text-[0.625rem] text-text-muted font-mono mt-1 opacity-50">{selectedSession?.session_id}</div>
            </div>
            <RetroButton
              variant="secondary"
              onClick={() => setActiveTab('history')}
              className="py-1 px-4 text-xs"
            >
              EXIT
            </RetroButton>
          </div>
          <SessionPlayback heartbeats={playbackData} session={selectedSession} />
        </div>
      )}
    </DashboardLayout>
  );
}

function App() {
  const [token, setToken] = useState<string | null>(sessionStorage.getItem("odisea_token"));

  if (!token) {
    return <LoginScreen onLogin={(t) => {
      sessionStorage.setItem("odisea_token", t);
      setToken(t);
    }} />;
  }

  return <Dashboard onLogout={() => {
    sessionStorage.removeItem("odisea_token");
    setToken(null);
  }} />;
}

export default App;
