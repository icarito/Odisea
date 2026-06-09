import { useState, useEffect } from 'react';
import { Toaster, toast } from 'react-hot-toast';
import { LoginScreen } from './components/LoginScreen';
import { PlayerCard } from './components/PlayerCard';
import { Viewport3D } from './components/Viewport3D';
import { FpsTimeline } from './components/FpsTimeline';
import { MemTimeline } from './components/MemTimeline';
import { SessionTimeline } from './components/SessionTimeline';
import { SessionHistory } from './components/SessionHistory';
import { useTelemetry } from './hooks/useTelemetry';

function Dashboard({ onLogout }: { onLogout: () => void }) {
  const { heartbeats, peersConnected, isConnected, alerts, history } = useTelemetry();
  const [selectedPlayerId, setSelectedPlayerId] = useState<string | null>(null);

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

  const pids = Object.keys(heartbeats);
  const activeId = selectedPlayerId || pids[0];
  const activeHb = heartbeats[activeId];
  const activeHistory = history[activeId];

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
        {/* Left Sidebar - Player List & History */}
        <div className="w-64 border-r border-border-custom flex flex-col bg-bg-primary">
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
          <div className="flex-1 overflow-y-auto p-2 flex flex-col gap-2">
            {!showHistory ? (
              <>
                {pids.length === 0 && <div className="text-center text-text-muted py-10 text-sm">Sin players</div>}
                {pids.map(pid => (
                  <PlayerCard
                    key={pid}
                    hb={heartbeats[pid]}
                    isActive={activeId === pid}
                    onClick={() => setSelectedPlayerId(pid)}
                  />
                ))}
              </>
            ) : (
              <SessionHistory />
            )}
          </div>
        </div>

        {/* Center - 3D Viewport & Charts */}
        <div className="flex-1 flex flex-col overflow-hidden">
          <div className="flex-1 relative p-4">
            {activeHb ? (
              <Viewport3D
                position={activeHb.player?.position || [0, 0, 0]}
                yaw={activeHb.player?.yaw || 0}
                pitch={activeHb.player?.pitch || 0}
                roll={activeHb.player?.roll || 0}
                trail={activeHistory?.trail || []}
                follow={followPlayer}
                wireframe={wireframe}
                sceneName={manualScene || activeHb.player?.scene || "Unknown"}
              />
            ) : (
              <div className="w-full h-full bg-black rounded-lg border border-border-custom flex items-center justify-center text-text-muted">
                Seleccioná un player para ver telemetría 3D
              </div>
            )}

            {/* Viewport Overlays */}
            {activeHb && (
              <div className="absolute top-6 right-6 flex flex-col gap-2 bg-bg-card/90 p-3 rounded border border-border-custom text-[10px]">
                <div className="flex justify-between gap-4">
                  <span className="text-text-muted">POS</span>
                  <span>{(activeHb.player?.position || [0, 0, 0]).map(n => typeof n === 'number' ? n.toFixed(2) : '0.00').join(", ")}</span>
                </div>
                <div className="flex justify-between gap-4">
                  <span className="text-text-muted">ROT</span>
                  <span>Y:{(activeHb.player?.yaw || 0).toFixed(2)} P:{(activeHb.player?.pitch || 0).toFixed(2)}</span>
                </div>
              </div>
            )}

            <div className="absolute bottom-6 left-6 flex items-center gap-2">
              <select
                value={manualScene || activeHb?.player.scene || ""}
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
            </div>
          </div>

          <div className="h-60 border-t border-border-custom flex flex-col bg-bg-card p-4 gap-4">
            <div className="flex-1 flex gap-4 overflow-hidden">
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
        </div>

        {/* Right Sidebar - Alerts */}
        <div className="w-72 border-l border-border-custom flex flex-col bg-bg-primary">
          <div className="p-3 text-[10px] uppercase text-text-muted font-bold border-b border-border-custom">
            Alertas / Log
          </div>
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
