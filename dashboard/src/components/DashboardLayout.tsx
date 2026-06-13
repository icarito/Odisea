import React from 'react';
import { Activity, Map, Clock, Users, LogOut, Globe, Settings } from 'lucide-react';
import { RetroTabs } from './retro';
import { buildLabel } from '../lib/buildLabels';

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
}

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
  latestPublished,
  secondaryNav,
}) => {
  const publishedLabel = buildLabel(latestPublished);
  // Date of the currently published build, shown next to the version so "which
  // version" reads as a human date, not just a hash.
  const publishedDate = latestPublished?.timestamp
    ? new Date(latestPublished.timestamp * 1000).toLocaleDateString('es', { day: '2-digit', month: 'short' })
    : '';
  const tabs = [
    { id: 'live', label: 'Live', icon: <Activity size={24} /> },
    { id: 'mapa', label: 'Globe', icon: <Globe size={24} /> },
    { id: 'heatmap', label: 'Heatmap', icon: <Map size={24} /> },
    { id: 'history', label: 'History', icon: <Clock size={24} /> },
  ];

  return (
    <div className="flex flex-col h-screen bg-bg-primary overflow-hidden font-mono crt-effect">
      {/* Fixed header */}
      <header className="relative shrink-0 flex flex-col gap-2 px-3 py-2 border-b-4 border-black bg-bg-card z-30 sm:flex-row sm:items-center sm:justify-between sm:px-4">
        <h1 className="text-accent font-black text-sm italic leading-none tracking-tighter sm:text-base">
          <button type="button" onClick={() => setActiveTab('live')} className="hover:text-text-primary">
            <span className="block sm:inline">ODISEA</span>
          </button>
          <span className="ml-2 align-middle text-[0.5rem] font-bold not-italic tracking-normal text-text-muted">
            dash {dashboardVersion || 'dev'}
            {publishedLabel ? (
              <> · pub {publishedLabel}{publishedDate ? ` (${publishedDate})` : ''}</>
            ) : null}
          </span>
        </h1>

        <div className="flex min-w-0 items-center justify-between gap-2 sm:justify-end sm:gap-4">
          {activePlayerMeta}
          {headerControls}

          <span className="flex items-center gap-1.5 text-[0.625rem] uppercase font-bold">
            <span className={`w-2 h-2 rounded-full ${isConnected ? 'bg-success shadow-[0_0_8px_rgba(63,185,80,0.5)]' : 'bg-danger'}`} />
            <span className={isConnected ? 'text-success' : 'text-danger'}>{isConnected ? 'on' : 'off'}</span>
          </span>

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

      {/* Fixed bottom nav */}
      <nav className="shrink-0 border-t-4 border-black bg-bg-card z-30">
        <RetroTabs tabs={tabs} activeTab={activeTab} onTabChange={setActiveTab} />
      </nav>
    </div>
  );
};
