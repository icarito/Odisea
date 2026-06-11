import { useState, useEffect } from 'react';
import { Toaster, toast } from 'react-hot-toast';
import { LoginScreen } from './components/LoginScreen';
import { PlayerCard } from './components/PlayerCard';
import { Viewport3D } from './components/Viewport3D';
import { FpsTimeline } from './components/FpsTimeline';
import { MemTimeline } from './components/MemTimeline';
import { SessionTimeline } from './components/SessionTimeline';
import { SessionHistory } from './components/SessionHistory';
import { WebLoads } from './components/WebLoads';
import { useTelemetry } from './hooks/useTelemetry';
import { getHeatmap } from './api';

function Dashboard({ onLogout }: { onLogout: () => void }) {
  const { heartbeats, peersConnected, heartbeatRate, isConnected, alerts, history } = useTelemetry();
  const [selectedPlayerId, setSelectedPlayerId] = useState<string | null>(null);
  const [heatmapData, setHeatmapData] = useState<any[] | undefined>();
  const [showHeatmap, setShowHeatmap] = useState(false);
  const [showLiveGhosts, setShowLiveGhosts] = useState(true);

  useEffect(() => {
    if (alerts.length > 0) {
        const latest = alerts[0];
        toast(latest.message, {
            icon: latest.type === 'disconnect' ? '❌' : '⚠️',
            style: {
                borderRadius: '4px',
                background: '#13161c',
                color: '#d7dbe0',
                border: '1px solid #232833',
                fontSize: '12px',
                fontFamily: 'monospace'
            },
        });
    }
  }, [alerts]);
  const [showHistory, setShowHistory] = useState(false);
  const [followPlayer, setFollowPlayer] = useState(true);
  const [wireframe, setWireframe] = useState(false);
  const [manualScene, setManualScene] = useState<string | null>(null);
  const [collapsed, setCollapsed] = useState<Record<string, boolean>>({ players: false, timeline: false, alerts: false, webloads: false });

  const toggleCollapse = (section: string) => setCollapsed(prev => ({ ...prev, [section]: !prev[section] }));

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

  // Helper para garantizar que la posición sea un array de 3 números
  const safePos = (p: any): [number, number, number] => {
    if (Array.isArray(p) && p.length >= 3) {
      return [Number(p[0]), Number(p[1]), Number(p[2])];
    }
    return [0, 0, 0];
  };

  return (
    <div className="min-h-screen bg-bg-primary text-text-primary font-mono flex flex-col">
      <Toaster position="bottom-right" />
      <header className="flex items-center gap-4 px-4 py-2 bg-bg-card border-b border-border-custom sticky top-0 z-20">
        <h1 className="text-accent font-bold text-base">ODISEA CENTRAL</h1>
        <div className="flex items-center gap-4 text-xs">
          <span className="flex items-center gap-1.5">
            <div className={`w-2 h-2 rounded-full ${isConnected ? 'bg-success' : 'bg-danger'}`} />
            {isConnected ? 'online' : 'offline'}
          </span>
          <span className="text-text-muted">peers <b className="text-text-primary">{peersConnected}</b></span>
          <span className="text-text-muted">hb/s <b className="text-text-primary">{typeof heartbeatRate === 'number' ? heartbeatRate.toFixed(1) : heartbeatRate}</b></span>
          <span className="text-text-muted">refresco <b className="text-text-primary">1s</b></span>
        </div>
        <div className="flex-1" />
        <button
          onClick={onLogout}
          className="px-3 py-1 bg-bg-primary border border-border-custom rounded text-xs hover:bg-[#1c2230]"
        >
          salir
        </button>
      </header>

      <main className="flex-1 flex overflow-hidden">
        {/* Left Sidebar - Player List & History (Hidden on small screens) */}
        <div className="hidden lg:flex lg:w-64 lg:shrink-0 flex-col bg-bg-primary border-r border-border-custom">
          <div className="flex border-b border-border-custom">
            <button
              onClick={() => setShowHistory(false)}
              className={`flex-1 p-3 text-[10px] uppercase font-bold ${!showHistory ? 'text-accent border-b-2 border-accent' : 'text-text-muted hover:text-text-primary'}`}
            >
              Players ({pids.length})
            </button>
            <button
              onClick={() => setShowHistory(true)}
              className={`flex-1 p-3 text-[10px] uppercase font-bold ${showHistory ? 'text-accent border-b-2 border-accent' : 'text-text-muted hover:text-text-primary'}`}
            >
              Sesiones
            </button>
          </div>
          <div
            className="p-2 text-[10px] uppercase text-text-muted font-bold border-b border-border-custom cursor-pointer hover:text-text-primary select-none flex justify-between items-center"
            onClick={() => toggleCollapse('players')}
          >
            <span>{!showHistory ? 'Players online' : 'Sesiones'}</span>
            <span className="text-xs">{collapsed.players ? '▸' : '▾'}</span>
          </div>
          {!collapsed.players ? (
          <div className="flex-1 overflow-y-auto overflow-x-hidden p-2 flex flex-col gap-2">
            {!showHistory ? (
              <>
                {pids.length === 0 && <div className="text-center text-text-muted py-10 text-sm">Sin players</div>}
                {pids.map(pid => {
                  const hb = heartbeats[pid];
                  const ts = typeof hb.timestamp === 'number' ? hb.timestamp : 0;
                  const age_s = (Date.now() - ts * 1000) / 1000;
                  return (
                  <PlayerCard
                    key={pid}
                    hb={hb}
                    isActive={activeId === pid}
                    onClick={() => setSelectedPlayerId(pid)}
                    staleAge={age_s}
                  />
                  );
                })}
              </>
            ) : (
              <SessionHistory />
            )}
          </div>
          ) : null}
        </div>

        {/* Center - 3D Viewport & Charts */}
        <div className="flex-1 flex flex-col overflow-hidden min-w-0">
          <div className={`${collapsed.timeline ? 'flex-1' : 'shrink-0'} p-4`}>
            <div className={`${collapsed.timeline ? '' : 'h-[400px]'} w-full relative`}>
            {activeHb?.player ? (
              <>
                <Viewport3D
                  position={safePos(activeHb.player.position)}
                  yaw={Number(activeHb.player.yaw) || 0}
                  pitch={Number(activeHb.player.pitch) || 0}
                  roll={Number(activeHb.player.roll) || 0}
                  trail={activeHistory?.trail || []}
                  follow={followPlayer}
                  wireframe={wireframe}
                  sceneName={manualScene || activeHb.player.scene || "Unknown"}
                  staleAge={staleAge}
                  heatmapData={heatmapData}
                  liveGhosts={showLiveGhosts ? Object.values(heartbeats).filter(h => h.player_id !== activeId) : []}
                />
                
                {/* Viewport Overlays */}
                <div className="absolute top-6 right-6 flex flex-col gap-2 bg-bg-card/90 p-3 rounded border border-border-custom text-[10px] pointer-events-none">
                  <div className="flex justify-between gap-4">
                    <span className="text-text-muted">POS</span>
                    <span>{safePos(activeHb.player.position).map(n => n.toFixed(2)).join(", ")}</span>
                  </div>
                  <div className="flex justify-between gap-4">
                    <span className="text-text-muted">ROT</span>
                    <span>Y:{(Number(activeHb.player.yaw) || 0).toFixed(2)} P:{(Number(activeHb.player.pitch) || 0).toFixed(2)}</span>
                  </div>
                </div>

                <div className="absolute bottom-6 left-6 flex items-center gap-2 pointer-events-auto">
                  <select
                    value={manualScene || activeHb.player.scene || ""}
                    onChange={(e) => setManualScene(e.target.value)}
                    className="bg-bg-card/80 border border-border-custom text-[10px] px-2 py-1.5 rounded outline-none"
                  >
                    <option value="">Auto Scene</option>
                    <option value="Dome_Crio">Dome_Crio</option>
                    <option value="Exterior">Exterior</option>
                    <option value="ZeroG">ZeroG</option>
                  </select>
                  <button
                    onClick={() => setFollowPlayer(!followPlayer)}
                    className={`px-3 py-1.5 rounded text-xs border ${followPlayer ? 'bg-accent text-bg-primary border-accent' : 'bg-bg-card/80 border-border-custom'}`}
                  >
                    Seguir Player
                  </button>
                  <button
                    onClick={() => setWireframe(!wireframe)}
                    className={`px-3 py-1.5 rounded text-xs border ${wireframe ? 'bg-accent text-bg-primary border-accent' : 'bg-bg-card/80 border-border-custom'}`}
                  >
                    Wireframe
                  </button>
                  <button
                    onClick={() => setShowHeatmap(!showHeatmap)}
                    className={`px-3 py-1.5 rounded text-xs border ${showHeatmap ? 'bg-accent text-bg-primary border-accent' : 'bg-bg-card/80 border-border-custom'}`}
                  >
                    Heatmap
                  </button>
                  <button
                    onClick={() => setShowLiveGhosts(!showLiveGhosts)}
                    className={`px-3 py-1.5 rounded text-xs border ${showLiveGhosts ? 'bg-accent text-bg-primary border-accent' : 'bg-bg-card/80 border-border-custom'}`}
                  >
                    Live Ghosts
                  </button>
                </div>
              </>
            ) : (
              <div className="w-full h-full bg-black rounded-lg border border-border-custom flex items-center justify-center text-text-muted">
                {activeHb ? "Esperando datos del jugador..." : "Seleccioná un player para ver telemetría 3D"}
              </div>
            )}
            </div>
          </div>

          <div className={`border-t border-border-custom flex flex-col bg-bg-card ${collapsed.timeline ? '' : 'flex-1'}`}>
            <div
              className="p-2 text-[10px] uppercase text-text-muted font-bold cursor-pointer hover:text-text-primary select-none flex justify-between items-center"
              onClick={() => toggleCollapse('timeline')}
            >
              <span>Charts & Timeline</span>
              <span className="text-xs">{collapsed.timeline ? '▸' : '▾'}</span>
            </div>
            {!collapsed.timeline && (
            <div className="p-4 gap-4 flex flex-col">
            <div className="flex gap-4 overflow-hidden" style={{ height: 200 }}>
                <div className="flex-1 flex flex-col gap-1 min-w-0">
                <span className="text-[10px] uppercase text-text-muted font-bold">FPS Timeline</span>
                <FpsTimeline data={activeHistory?.fps || []} />
                </div>
                <div className="flex-1 flex flex-col gap-1 min-w-0">
                <span className="text-[10px] uppercase text-text-muted font-bold">Memoria (MB)</span>
                <MemTimeline data={activeHistory?.memory || []} />
                </div>
            </div>
            <div className="flex flex-col gap-1">
                <div className="flex justify-between items-center">
                    <span className="text-[10px] uppercase text-text-muted font-bold">Session Timeline</span>
                    {activeHistory?.events.length > 0 && (
                        <span className="text-[10px] text-text-muted">
                            Duration: {Math.round(activeHistory.events[activeHistory.events.length-1].timestamp - activeHistory.events[0].timestamp)}s
                        </span>
                    )}
                </div>
                <SessionTimeline events={activeHistory?.events || []} />
            </div>
            </div>
            )}
          </div>
        </div>

        {/* Right Sidebar - Web Loads & Alerts (Hidden on small/medium screens) */}
        <div className={`hidden xl:flex flex-col bg-bg-primary border-l border-border-custom ${collapsed.alerts ? 'w-auto xl:w-auto' : 'w-72 xl:w-72 xl:shrink-0'}`}>
          <div
            className="p-3 text-[10px] uppercase text-text-muted font-bold border-b border-border-custom cursor-pointer hover:text-text-primary select-none flex justify-between items-center"
            onClick={() => toggleCollapse('webloads')}
          >
            <span>Cargas Web</span>
            <span className="text-xs">{collapsed.webloads ? '▸' : '▾'}</span>
          </div>
          {!collapsed.webloads && (
          <div className="max-h-72 overflow-y-auto p-2 border-b border-border-custom">
            <WebLoads />
          </div>
          )}
          <div
            className="p-3 text-[10px] uppercase text-text-muted font-bold border-b border-border-custom cursor-pointer hover:text-text-primary select-none flex justify-between items-center"
            onClick={() => toggleCollapse('alerts')}
          >
            <span>Alertas / Log</span>
            <span className="text-xs">{collapsed.alerts ? '▸' : '▾'}</span>
          </div>
          {!collapsed.alerts && (
          <div className="flex-1 overflow-y-auto p-2 flex flex-col gap-2">
            {alerts.length === 0 && <div className="text-center text-text-muted py-10 text-sm">Sin alertas</div>}
            {alerts.map(alert => (
              <div key={alert.id} className="p-2 border border-border-custom bg-bg-card rounded text-xs">
                 <div className="flex justify-between mb-1">
                    <span className={`uppercase font-bold ${alert.type === 'disconnect' ? 'text-danger' : 'text-warning'}`}>{alert.type}</span>
                    <span className="text-text-muted">{new Date(alert.timestamp).toLocaleTimeString()}</span>
                 </div>
                 <div>{alert.message}</div>
              </div>
              ))}
          </div>
          )}
        </div>
      </main>
    </div>
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
