import React, { useEffect, useRef, useState } from 'react';
import { Activity, Map, Clock, Users, LogOut, Globe, Settings, Loader2, ExternalLink } from 'lucide-react';
import { RetroTabs } from './retro';
import { buildLabel } from '../lib/buildLabels';

// In-flight GitHub Actions run, surfaced in the header "PUBLICANDO" indicator.
export interface RunningAction {
  id: number;
  name: string;
  status: string; // queued | in_progress
  html_url: string;
  created_at: string;
}

interface DashboardLayoutProps {
  children: React.ReactNode;
  onLogout: () => void;
  isConnected: boolean;
  activeTab: string;
  setActiveTab: (tab: any) => void;
  playerCount: number;
  playerCountLabel?: string;
  onPlayersClick: () => void;
  // Compact live metadata for the currently focused/active player, shown in the
  // header when there is one.
  activePlayerMeta?: React.ReactNode;
  headerControls?: React.ReactNode;
  settingsPanel?: React.ReactNode;
  playerFocus?: React.ReactNode;
  showSettings?: boolean;
  onToggleSettings?: () => void;
  dashboardVersion?: string;
  // Unix seconds when the deployed dashboard was last written (index.html mtime),
  // from /health. Shown as a date next to the dashboard version.
  dashboardDeployedAt?: number | null;
  latestPublished?: {
    game_version?: string;
    git_commit?: string;
    build_id?: string;
    build_channel?: string;
    timestamp?: number;
  };
  // Optional second-level bar rendered just above the bottom nav (e.g. the
  // Live-tab view switcher). Hidden when not provided.
  secondaryNav?: React.ReactNode;
  // GitHub Actions runs currently in flight. When non-empty the connection
  // indicator turns amber ("PUBLICANDO") and becomes clickable to list them.
  runningActions?: RunningAction[];
}

// Connection / CI status indicator. Green "on" / red "off" by default; turns
// amber "PUBLICANDO" while GitHub Actions runs are in flight, and clicking it
// then reveals the pending runs in a popover.
const StatusIndicator: React.FC<{ isConnected: boolean; runningActions: RunningAction[] }> = ({
  isConnected,
  runningActions,
}) => {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const publishing = runningActions.length > 0;

  // Close the popover on outside click.
  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', onDown);
    return () => document.removeEventListener('mousedown', onDown);
  }, [open]);

  const dotClass = publishing
    ? 'bg-warning shadow-[0_0_8px_rgba(210,153,34,0.6)] animate-pulse'
    : isConnected
      ? 'bg-success shadow-[0_0_8px_rgba(63,185,80,0.5)]'
      : 'bg-danger';
  const textClass = publishing ? 'text-warning' : isConnected ? 'text-success' : 'text-danger';
  const label = publishing ? `publicando${runningActions.length > 1 ? ` (${runningActions.length})` : ''}` : isConnected ? 'on' : 'off';

  const fmt = (iso: string) => {
    const d = new Date(iso);
    return Number.isNaN(d.getTime()) ? '' : d.toLocaleTimeString('es', { hour: '2-digit', minute: '2-digit' });
  };

  return (
    <div className="relative" ref={ref}>
      <button
        type="button"
        onClick={() => publishing && setOpen((v) => !v)}
        className={`flex items-center gap-1.5 text-[0.625rem] uppercase font-bold ${publishing ? 'cursor-pointer' : 'cursor-default'}`}
        title={publishing ? 'Acciones en curso — clic para ver' : isConnected ? 'Telemetría conectada' : 'Sin conexión'}
        aria-haspopup={publishing ? 'menu' : undefined}
        aria-expanded={publishing ? open : undefined}
      >
        <span className={`w-2 h-2 rounded-full ${dotClass}`} />
        <span className={textClass}>{label}</span>
      </button>

      {open && publishing && (
        <>
          {/* Mobile: dim backdrop so the panel reads as a sheet, not a clipped
              dropdown. Tapping it closes. Hidden on sm+ (anchored dropdown). */}
          <div
            className="fixed inset-0 z-40 bg-black/40 sm:hidden"
            onClick={() => setOpen(false)}
            aria-hidden
          />
          {/* On mobile the panel is pinned across the viewport (insets) just below
              the header; on sm+ it anchors to the indicator as a dropdown. */}
          <div
            className="fixed inset-x-3 top-16 z-50 border-4 border-black bg-bg-card shadow-[4px_4px_0px_0px_black]
                       sm:absolute sm:inset-x-auto sm:right-0 sm:top-full sm:mt-2 sm:w-64"
            role="menu"
          >
            <div className="border-b-2 border-black px-3 py-1.5 text-[0.625rem] font-black uppercase tracking-widest text-warning">
              Acciones en curso ({runningActions.length})
            </div>
            <ul className="max-h-[60vh] overflow-y-auto sm:max-h-64">
              {runningActions.map((run) => (
                <li key={run.id} className="border-b border-black/40 last:border-b-0">
                  <a
                    href={run.html_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="flex items-center justify-between gap-2 px-3 py-2 text-[0.625rem] hover:bg-bg-primary"
                  >
                    <span className="flex min-w-0 items-center gap-1.5">
                      <Loader2 size={11} className="shrink-0 animate-spin text-warning" />
                      <span className="min-w-0">
                        <span className="block truncate font-bold text-text-primary">{run.name}</span>
                        <span className="text-text-muted">
                          {run.status === 'queued' ? 'en cola' : 'ejecutando'}{fmt(run.created_at) ? ` · ${fmt(run.created_at)}` : ''}
                        </span>
                      </span>
                    </span>
                    <ExternalLink size={11} className="shrink-0 text-accent" />
                  </a>
                </li>
              ))}
            </ul>
          </div>
        </>
      )}
    </div>
  );
};

// Unified mobile-first layout: fixed header + fixed bottom nav, scrollable
// content in between. The same structure scales up to desktop (just wider).
export const DashboardLayout: React.FC<DashboardLayoutProps> = ({
  children,
  onLogout,
  isConnected,
  activeTab,
  setActiveTab,
  playerCount,
  playerCountLabel,
  onPlayersClick,
  activePlayerMeta,
  headerControls,
  settingsPanel,
  playerFocus,
  showSettings,
  onToggleSettings,
  dashboardVersion,
  dashboardDeployedAt,
  latestPublished,
  secondaryNav,
  runningActions = [],
}) => {
  const publishedLabel = buildLabel(latestPublished);
  const fmtDate = (sec?: number | null) => (
    sec ? new Date(sec * 1000).toLocaleString('es', {
      day: '2-digit',
      month: 'short',
      hour: '2-digit',
      minute: '2-digit',
    }) : ''
  );
  // Deploy date of this dashboard build, shown next to its version so "which
  // version" reads as a human date, not just a hash.
  const dashDate = fmtDate(dashboardDeployedAt);
  const publishedDate = fmtDate(latestPublished?.timestamp);
  const tabs = [
    { id: 'live', label: 'Live', icon: <Activity size={24} /> },
    { id: 'mapa', label: 'Globe', icon: <Globe size={24} /> },
    { id: 'heatmap', label: 'Heatmap', icon: <Map size={24} /> },
    { id: 'history', label: 'History', icon: <Clock size={24} /> },
  ];

  return (
    <div className="app-shell flex flex-col bg-bg-primary overflow-hidden font-mono crt-effect">
      {/* Fixed header — top safe-area inset keeps it clear of the status bar. */}
      <header
        className="relative shrink-0 flex flex-col gap-2 px-3 py-2 border-b-4 border-black bg-bg-card z-30 sm:flex-row sm:items-center sm:justify-between sm:px-4"
        style={{ paddingTop: 'max(0.5rem, env(safe-area-inset-top, 0px))' }}
      >
        <h1 className="text-accent font-black text-sm italic leading-none tracking-tighter sm:text-base">
          <button type="button" onClick={() => setActiveTab('live')} className="hover:text-text-primary">
            <span className="block sm:inline">ODISEA</span>
          </button>
          <span className="ml-2 align-middle text-[0.5rem] font-bold not-italic tracking-normal text-text-muted">
            dash {dashboardVersion || 'dev'}{dashDate ? ` (${dashDate})` : ''}
            {publishedLabel ? (
              <> · pub {publishedLabel}{publishedDate ? ` (${publishedDate})` : ''}</>
            ) : null}
          </span>
        </h1>

        <div className="flex min-w-0 items-center justify-between gap-2 sm:justify-end sm:gap-4">
          {activePlayerMeta}
          {headerControls}

          {/* Acceso a la nueva IA incident-first (rediseño en curso). */}
          <a
            href="/investigate"
            className="border-2 border-accent bg-accent/10 px-2 py-1 text-[0.625rem] font-black uppercase text-accent transition-colors hover:bg-accent hover:text-black"
            title="Nueva vista de incidentes"
          >
            Incidentes ▸
          </a>

          <StatusIndicator isConnected={isConnected} runningActions={runningActions} />

          {/* Player count -> opens the bottom sheet */}
          <button
            onClick={onToggleSettings}
            className="p-1.5 border-2 border-black bg-bg-primary hover:bg-accent hover:text-black transition-colors"
            title="Settings"
          >
            <Settings size={14} />
          </button>

          <button
            onClick={onPlayersClick}
            className="flex items-center gap-1.5 px-2 py-1 border-2 border-black bg-bg-primary text-[0.625rem] font-bold uppercase hover:bg-accent hover:text-black transition-colors"
          >
            <Users size={14} />
            {playerCountLabel || `${playerCount} ${playerCount === 1 ? 'player' : 'players'}`}
          </button>

          <button
            onClick={onLogout}
            className="p-1.5 border-2 border-black bg-bg-primary hover:bg-danger hover:text-black transition-colors"
            title="Log out"
          >
            <LogOut size={14} />
          </button>
        </div>
        {playerFocus && (
          <div className="fixed right-2 top-2 z-50 sm:absolute sm:left-1/2 sm:right-auto sm:top-1/2 sm:-translate-x-1/2 sm:-translate-y-1/2">
            {playerFocus}
          </div>
        )}
      </header>

      {/* Scrollable content */}
      <main className="flex-1 min-h-0 overflow-y-auto overflow-x-hidden">
        {showSettings && settingsPanel && (
          <div className="sticky top-0 z-20 bg-bg-card border-b-2 border-black px-3 py-3">
            {settingsPanel}
          </div>
        )}
        {children}
      </main>

      {/* Optional second-level bar (e.g. Live view switcher) */}
      {secondaryNav && (
        <div className="shrink-0 border-t-2 border-black bg-bg-card/80 z-30">
          {secondaryNav}
        </div>
      )}

      {/* Fixed bottom nav — bottom safe-area inset keeps it above the Android
          navigation bar / iOS home indicator. */}
      <nav
        className="shrink-0 border-t-4 border-black bg-bg-card z-30"
        style={{ paddingBottom: 'env(safe-area-inset-bottom, 0px)' }}
      >
        <RetroTabs tabs={tabs} activeTab={activeTab} onTabChange={setActiveTab} />
      </nav>
    </div>
  );
};
