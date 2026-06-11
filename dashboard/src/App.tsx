import { useState, useEffect, useRef } from 'react';
import { Toaster, toast } from 'react-hot-toast';
import { LoginScreen } from './components/LoginScreen';
import { PlayerCard } from './components/PlayerCard';
import { Viewport3D } from './components/Viewport3D';
import { FpsTimeline } from './components/FpsTimeline';
import { MemTimeline } from './components/MemTimeline';
import { Heatmap3D } from './components/Heatmap3D';
import { LiveMap } from './components/LiveMap';
import { HistoricalTable } from './components/HistoricalTable';
import { SessionPlayback } from './components/SessionPlayback';
import { DashboardLayout } from './components/DashboardLayout';
import { RetroCard, RetroButton, RetroBadge, RetroSelect, RetroInput } from './components/retro';
import { useTelemetry } from './hooks/useTelemetry';
import { useWebSocket } from './hooks/useWebSocket';
import { useLayoutPersistence } from './hooks/useLayoutPersistence';
import { getHeatmap, getHistoricalSessions, getGhostData, getScenes } from './api';
import { Maximize2, Map as MapIcon, Info, Play } from 'lucide-react';
import { Panel, PanelGroup, PanelResizeHandle } from 'react-resizable-panels';

type Tab = 'live' | 'heatmap' | 'history' | 'playback';

function Dashboard({ onLogout }: { onLogout: () => void }) {
  const { heartbeats, peersConnected, isConnected, alerts, history } = useTelemetry();
  const { lastMessage } = useWebSocket();
  const { layout, updateLayout } = useLayoutPersistence();
  
  const activeTab = layout.activeTab as Tab;
  const setActiveTab = (t: Tab) => updateLayout({ activeTab: t });

  const [selectedPlayerId, setSelectedPlayerId] = useState<string | null>(null);
  const [heatmapData, setHeatmapData] = useState<any[] | undefined>();
  const [showHeatmap, setShowHeatmap] = useState(false);
  const [showLiveGhosts, setShowLiveGhosts] = useState(true);
  const accelerometerEnabled = layout.accelerometerEnabled;
  const setAccelerometerEnabled = (v: boolean) => updateLayout({ accelerometerEnabled: v });

  // Responsive state
  const [isMobile, setIsMobile] = useState(window.innerWidth < 640);
  const [isDesktop, setIsDesktop] = useState(window.innerWidth >= 1024);

  useEffect(() => {
    const handleResize = () => {
      setIsMobile(window.innerWidth < 640);
      setIsDesktop(window.innerWidth >= 1024);
    };
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

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

  const viewportRef = useRef<HTMLDivElement>(null);

  const toggleFullscreen = async () => {
    if (!viewportRef.current) return;
    try {
      if (document.fullscreenElement) {
        await document.exitFullscreen();
      } else {
        await viewportRef.current.requestFullscreen();
        try {
          if ('orientation' in screen && (screen.orientation as any).lock) {
            await (screen.orientation as any).lock('landscape');
          }
        } catch (e) {
          console.warn("Could not lock orientation", e);
        }
      }
    } catch (e) {
      toast.error("Fullscreen not supported");
    }
  };

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

  const renderPlayerList = () => (
    <div className="flex flex-col gap-2">
      {pids.length === 0 && <div className="text-center text-text-muted py-10 text-sm">Sin players</div>}
      {pids.map(pid => (
        <PlayerCard
          key={pid}
          hb={heartbeats[pid]}
          isActive={activeId === pid}
          onClick={() => setSelectedPlayerId(pid)}
          staleAge={(Date.now() - heartbeats[pid].timestamp * 1000) / 1000}
        />
      ))}
    </div>
  );

  return (
    <DashboardLayout
      onLogout={onLogout}
      peersConnected={Number(peersConnected) || 0}
      isConnected={isConnected}
      activeTab={activeTab}
      setActiveTab={setActiveTab}
      playerList={renderPlayerList()}
      isSessionSelected={!!selectedSession}
    >
      <Toaster position="bottom-right" />
      
      {activeTab === 'live' && (
        <div className="flex flex-col h-full overflow-hidden">
          {isDesktop ? (
            <PanelGroup direction="vertical">
              <Panel defaultSize={70} minSize={30}>
                <PanelGroup direction="horizontal">
                  <Panel className="relative">
                    <div ref={viewportRef} className="h-full w-full">
                        <Viewport3D
                            position={activeHb ? safePos(activeHb.player.position) : [0,0,0]}
                            yaw={activeHb ? Number(activeHb.player.yaw) || 0 : 0}
                            pitch={activeHb ? Number(activeHb.player.pitch) || 0 : 0}
                            roll={activeHb ? Number(activeHb.player.roll) || 0 : 0}
                            trail={activeHistory?.trail || []}
                            follow={followPlayer}
                            wireframe={wireframe}
                            sceneName={manualScene || activeHb?.player.scene || ""}
                            staleAge={staleAge}
                            heatmapData={showHeatmap ? heatmapData : undefined}
                            liveGhosts={showLiveGhosts ? Object.values(heartbeats).filter(h => h.player_id !== activeId) : []}
                        />
                        {/* Overlays */}
                        <div className="absolute top-4 right-4 flex flex-col gap-2 pointer-events-none">
                            {activeHb?.player && (
                                <RetroCard className="py-2 px-3 text-[0.625rem] bg-bg-card/80">
                                    <div className="flex justify-between gap-4 mb-1 border-b border-black/20 pb-1">
                                        <span className="text-text-muted">POS</span>
                                        <span className="font-bold">{safePos(activeHb.player.position).map(n => n.toFixed(1)).join(", ")}</span>
                                    </div>
                                    <div className="flex justify-between gap-4">
                                        <span className="text-text-muted">SCN</span>
                                        <span className="text-accent truncate max-w-[80px]">{activeHb.player.scene}</span>
                                    </div>
                                </RetroCard>
                            )}
                        </div>

                        <div className="absolute bottom-4 left-4 right-4 flex items-center justify-between gap-2 pointer-events-auto">
                            <div className="flex gap-2">
                                <RetroSelect
                                    value={manualScene || activeHb?.player.scene || ""}
                                    onChange={(e) => setManualScene(e.target.value)}
                                    className="py-1 px-2 text-[0.625rem] w-32"
                                >
                                    <option value="">AUTO SCENE</option>
                                    {scenes.map(s => <option key={s} value={s}>{s}</option>)}
                                </RetroSelect>
                                <RetroButton 
                                    variant={followPlayer ? 'primary' : 'secondary'} 
                                    onClick={() => setFollowPlayer(!followPlayer)}
                                    className="py-1 px-3 text-[0.625rem]"
                                >
                                    FOLLOW
                                </RetroButton>
                                <RetroButton 
                                    variant={wireframe ? 'primary' : 'secondary'} 
                                    onClick={() => setWireframe(!wireframe)}
                                    className="py-1 px-3 text-[0.625rem]"
                                >
                                    MESH
                                </RetroButton>
                                <RetroButton 
                                    variant={showHeatmap ? 'primary' : 'secondary'} 
                                    onClick={() => setShowHeatmap(!showHeatmap)}
                                    className="py-1 px-3 text-[0.625rem]"
                                >
                                    HEAT
                                </RetroButton>
                                <RetroButton 
                                    variant={showLiveGhosts ? 'primary' : 'secondary'} 
                                    onClick={() => setShowLiveGhosts(!showLiveGhosts)}
                                    className="py-1 px-3 text-[0.625rem]"
                                >
                                    PEERS
                                </RetroButton>
                            </div>
                            <div className="flex gap-2">
                                <RetroButton 
                                    variant={accelerometerEnabled ? 'primary' : 'secondary'} 
                                    onClick={() => setAccelerometerEnabled(!accelerometerEnabled)}
                                    className="py-1 px-3 text-[0.625rem]"
                                >
                                    ACCEL
                                </RetroButton>
                                <RetroButton variant="secondary" onClick={toggleFullscreen} className="py-1 px-2">
                                    <Maximize2 size={14} />
                                </RetroButton>
                            </div>
                        </div>
                    </div>
                  </Panel>
                  <PanelResizeHandle className="w-1.5 bg-black hover:bg-accent transition-colors cursor-col-resize" />
                  <Panel defaultSize={30}>
                    <LiveMap ghosts={liveGhosts} sceneName={manualScene || activeHb?.player.scene || ""} />
                  </Panel>
                </PanelGroup>
              </Panel>
              <PanelResizeHandle className="h-1.5 bg-black hover:bg-accent transition-colors cursor-row-resize" />
              <Panel defaultSize={30} minSize={20}>
                <div className="h-full grid grid-cols-2 gap-4 p-4 overflow-hidden">
                    <RetroCard title="FPS TELEMETRY" className="flex flex-col min-h-0 h-full">
                        <FpsTimeline data={activeHistory?.fps || []} />
                    </RetroCard>
                    <RetroCard title="MEMORY USAGE (MB)" className="flex flex-col min-h-0 h-full">
                        <MemTimeline data={activeHistory?.memory || []} />
                    </RetroCard>
                </div>
              </Panel>
            </PanelGroup>
          ) : (
            <div className="flex flex-col gap-4">
              {!isMobile ? (
                  <div className="grid grid-cols-2 gap-4 h-[400px]">
                      <div className="relative border-4 border-black shadow-retro">
                        <Viewport3D
                             position={activeHb ? safePos(activeHb.player.position) : [0,0,0]}
                             yaw={activeHb ? Number(activeHb.player.yaw) || 0 : 0}
                             pitch={activeHb ? Number(activeHb.player.pitch) || 0 : 0}
                             roll={activeHb ? Number(activeHb.player.roll) || 0 : 0}
                             trail={activeHistory?.trail || []}
                             follow={followPlayer}
                             wireframe={wireframe}
                             sceneName={manualScene || activeHb?.player.scene || ""}
                             staleAge={staleAge}
                             heatmapData={showHeatmap ? heatmapData : undefined}
                             liveGhosts={showLiveGhosts ? Object.values(heartbeats).filter(h => h.player_id !== activeId) : []}
                        />
                         <div className="absolute top-2 right-2">
                            <RetroButton variant="secondary" onClick={toggleFullscreen} className="p-1">
                                <Maximize2 size={14} />
                            </RetroButton>
                         </div>
                      </div>
                      <div className="border-4 border-black shadow-retro">
                        <LiveMap ghosts={liveGhosts} sceneName={manualScene || activeHb?.player.scene || ""} />
                      </div>
                  </div>
              ) : (
                  <>
                    <RetroCard className="relative overflow-hidden">
                        {activeHb ? (
                            <div className="flex flex-col gap-3">
                                <div className="flex justify-between items-start">
                                    <div>
                                        <div className="text-[0.625rem] text-text-muted uppercase font-black mb-1">Active Subject</div>
                                        <div className="text-sm font-black text-accent truncate max-w-[200px]">{activeHb.player_id}</div>
                                    </div>
                                    <RetroBadge color={activeHb.player?.fps > 45 ? 'success' : activeHb.player?.fps > 30 ? 'warning' : 'danger'}>
                                        {activeHb.player?.fps || 0} FPS
                                    </RetroBadge>
                                </div>
                                <div className="grid grid-cols-2 gap-2 text-[0.625rem]">
                                    <div className="bg-black/20 p-2 border border-black/40">
                                        <div className="text-text-muted mb-1">POSITION</div>
                                        <div className="font-bold">{safePos(activeHb.player.position).map(n => n.toFixed(1)).join(", ")}</div>
                                    </div>
                                    <div className="bg-black/20 p-2 border border-black/40">
                                        <div className="text-text-muted mb-1">SCENE</div>
                                        <div className="font-bold text-accent truncate">{activeHb.player.scene}</div>
                                    </div>
                                </div>
                                <div className="flex gap-2 mt-2">
                                    <RetroButton onClick={toggleFullscreen} className="flex-1 py-3 flex items-center justify-center gap-2">
                                        <Maximize2 size={16} />
                                        <span>3D FULLSCREEN</span>
                                    </RetroButton>
                                    <RetroButton variant="secondary" onClick={() => setActiveTab('history')} className="px-4">
                                        <Info size={16} />
                                    </RetroButton>
                                </div>
                            </div>
                        ) : (
                            <div className="py-10 text-center text-text-muted italic">No active session selected</div>
                        )}
                        <div ref={viewportRef} className="hidden h-0 w-0">
                           <Viewport3D
                                position={activeHb ? safePos(activeHb.player.position) : [0,0,0]}
                                yaw={activeHb ? Number(activeHb.player.yaw) || 0 : 0}
                                pitch={activeHb ? Number(activeHb.player.pitch) || 0 : 0}
                                roll={activeHb ? Number(activeHb.player.roll) || 0 : 0}
                                trail={activeHistory?.trail || []}
                                follow={followPlayer}
                                wireframe={wireframe}
                                sceneName={manualScene || activeHb?.player.scene || ""}
                                staleAge={staleAge}
                                heatmapData={showHeatmap ? heatmapData : undefined}
                                liveGhosts={showLiveGhosts ? Object.values(heartbeats).filter(h => h.player_id !== activeId) : []}
                            />
                        </div>
                    </RetroCard>
                    
                    <RetroCard title="SESSION STATS" className="min-h-[200px]">
                        <FpsTimeline data={activeHistory?.fps || []} />
                    </RetroCard>
                  </>
              )}

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <RetroCard title="LIVE PEERS">
                     <div className="flex flex-wrap gap-2">
                        {liveGhosts.map(g => (
                            <div key={g.player_id} className="text-[0.625rem] bg-black/40 border border-black p-1 px-2 flex items-center gap-2">
                                <div className="w-1.5 h-1.5 rounded-full bg-success" />
                                <span>{g.player_id.substring(0, 8)}</span>
                            </div>
                        ))}
                        {liveGhosts.length === 0 && <span className="text-[0.625rem] italic text-text-muted">No other peers</span>}
                     </div>
                  </RetroCard>
              </div>
            </div>
          )}
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

          <div className="flex-1 relative border-4 border-black shadow-retro overflow-hidden">
            {isMobile ? (
                <div className="h-full flex flex-col p-4 overflow-y-auto">
                    <div className="flex flex-col items-center justify-center py-6 text-center gap-4">
                        <MapIcon size={48} className="text-accent opacity-50" />
                        <div>
                            <div className="font-black text-sm uppercase mb-1">Heatmap Analysis</div>
                            <p className="text-[0.625rem] text-text-muted leading-relaxed">
                                Full 3D visualization is resource intensive. <br/>
                                Summary: {heatmapData?.length || 0} active nodes detected.
                            </p>
                        </div>
                        <RetroButton onClick={toggleFullscreen} className="w-full flex items-center justify-center gap-2 py-3">
                            <Maximize2 size={16} />
                            <span>VIEW MAP (3D)</span>
                        </RetroButton>
                    </div>

                    <div className="mt-4 flex-1">
                        <div className="text-[0.625rem] font-black uppercase text-accent mb-3 tracking-widest flex items-center gap-2">
                            <Info size={12} /> Hot Cells Report
                        </div>
                        <div className="flex flex-col gap-2">
                            {(heatmapData || [])
                                .sort((a, b) => b.count - a.count)
                                .slice(0, 10)
                                .map((cell, idx) => (
                                <div key={idx} className="bg-black/20 border border-black/40 p-2 flex justify-between items-center">
                                    <div className="flex flex-col">
                                        <span className="text-[0.5rem] text-text-muted uppercase">Coordinates</span>
                                        <span className="text-[0.625rem] font-mono">X:{cell.x} Z:{cell.z}</span>
                                    </div>
                                    <div className="text-right">
                                        <div className="text-[0.5rem] text-text-muted uppercase">Intensity</div>
                                        <RetroBadge 
                                            color={cell.count > 50 ? 'danger' : cell.count > 20 ? 'warning' : 'success'}
                                            className="scale-75 origin-right"
                                        >
                                            {cell.count} PTS
                                        </RetroBadge>
                                    </div>
                                </div>
                            ))}
                            {(!heatmapData || heatmapData.length === 0) && (
                                <div className="text-[0.625rem] italic text-text-muted py-4 text-center">
                                    No heatmap data available for this scene.
                                </div>
                            )}
                        </div>
                    </div>

                    <div ref={viewportRef} className="hidden h-0 w-0">
                        <Heatmap3D data={heatmapData ?? []} resolution={heatmapRes} />
                    </div>
                </div>
            ) : (
                <Heatmap3D data={heatmapData ?? []} resolution={heatmapRes} />
            )}
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
