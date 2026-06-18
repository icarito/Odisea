import React from 'react';
import { LogOut, Users, Settings } from 'lucide-react';
import { buildLabel } from '../lib/buildLabels';
import { NavigationRail } from './NavigationRail';
import type { Tab } from '../types';

interface DashboardLayoutProps {
  children: React.ReactNode;
  onLogout: () => void;
  isConnected: boolean;
  activeTab: Tab;
  setActiveTab: (tab: Tab) => void;
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
  filterBar?: React.ReactNode;
  breadcrumb?: React.ReactNode;
}

// Unified layout with NavigationRail (desktop side, mobile bottom)
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
  filterBar,
  breadcrumb,
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
  const dashDate = fmtDate(dashboardDeployedAt);
  const publishedDate = fmtDate(latestPublished?.timestamp);

  return (
    <div className="flex h-screen w-screen bg-bg-primary overflow-hidden font-mono crt-effect">
      {/* Desktop side navigation */}
      <NavigationRail activeTab={activeTab} onTabChange={setActiveTab} className="hidden lg:flex" />

      <div className="flex flex-1 flex-col min-w-0">
        {/* Fixed header */}
        <header className="relative shrink-0 flex flex-col gap-2 px-3 py-2 border-b-4 border-black bg-bg-card z-30 sm:flex-row sm:items-center sm:justify-between sm:px-4">
          <h1 className="text-accent font-black text-sm italic leading-none tracking-tighter sm:text-base">
            <button type="button" onClick={() => setActiveTab('dashboard')} className="hover:text-text-primary">
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

            <span className="flex items-center gap-1.5 text-[0.625rem] uppercase font-bold">
              <span className={`w-2 h-2 rounded-full ${isConnected ? 'bg-success shadow-[0_0_8px_rgba(63,185,80,0.5)]' : 'bg-danger'}`} />
              <span className={isConnected ? 'text-success' : 'text-danger'}>{isConnected ? 'on' : 'off'}</span>
            </span>

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
              <span className="hidden sm:inline">{playerCountLabel || `${playerCount} ${playerCount === 1 ? 'player' : 'players'}`}</span>
              <span className="sm:hidden">{playerCount}</span>
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

        {/* Breadcrumb & Filter Bar */}
        <div className="shrink-0 flex flex-col">
          {breadcrumb}
          {filterBar}
        </div>

        {/* Scrollable content */}
        <main className="flex-1 min-h-0 overflow-y-auto overflow-x-hidden relative">
          {showSettings && settingsPanel && (
            <div className="sticky top-0 z-20 bg-bg-card border-b-2 border-black px-3 py-3">
              {settingsPanel}
            </div>
          )}
          {children}
        </main>

        {/* Optional second-level bar */}
        {secondaryNav && (
          <div className="shrink-0 border-t-2 border-black bg-bg-card/80 z-30">
            {secondaryNav}
          </div>
        )}

        {/* Mobile bottom navigation */}
        <NavigationRail activeTab={activeTab} onTabChange={setActiveTab} className="lg:hidden" isMobile />
      </div>
    </div>
  );
};
