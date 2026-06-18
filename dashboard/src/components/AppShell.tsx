import React from 'react';
import { Settings, Users, LogOut, Activity } from 'lucide-react';
import { NavigationRail } from './NavigationRail';
import { GlobalFilterBar } from './GlobalFilterBar';
import { BreadcrumbNav } from './BreadcrumbNav';
import { Tab } from '../types';

interface AppShellProps {
  children: React.ReactNode;
  activeTab: Tab;
  setActiveTab: (tab: Tab) => void;
  isConnected: boolean;
  playerCount: number;
  playerCountLabel?: string;
  onPlayersClick: () => void;
  onLogout: () => void;
  onToggleSettings: () => void;
  filters: any;
  onRemoveFilter: (type: string, value?: string) => void;
  navStack: { label: string; id: string }[];
  onNavigateBreadcrumb: (id: string) => void;
  activePlayerMeta?: React.ReactNode;
  headerControls?: React.ReactNode;
  settingsPanel?: React.ReactNode;
  showSettings?: boolean;
  dashboardVersion?: string;
}

export const AppShell: React.FC<AppShellProps> = ({
  children,
  activeTab,
  setActiveTab,
  isConnected,
  playerCount,
  playerCountLabel,
  onPlayersClick,
  onLogout,
  onToggleSettings,
  filters,
  onRemoveFilter,
  navStack,
  onNavigateBreadcrumb,
  activePlayerMeta,
  headerControls,
  settingsPanel,
  showSettings,
  dashboardVersion,
}) => {
  const isMobile = typeof window !== 'undefined' && window.innerWidth < 768;

  return (
    <div className="flex h-screen flex-col overflow-hidden bg-bg-primary font-mono crt-effect">
      {/* Header */}
      <header className="relative z-40 flex shrink-0 items-center justify-between border-b-4 border-black bg-bg-card px-4 py-2">
        <div className="flex items-center gap-3">
          <h1 className="text-sm font-black italic tracking-tighter text-accent sm:text-base">
            ODISEA <span className="not-italic text-text-muted">CENTRAL</span>
          </h1>
          <div className="hidden h-4 w-px bg-black/20 sm:block" />
          <div className="hidden items-center gap-2 sm:flex">
            <span className={`h-2 w-2 rounded-full ${isConnected ? 'bg-success shadow-[0_0_8px_rgba(63,185,80,0.5)]' : 'bg-danger'}`} />
            <span className={`text-[0.625rem] font-black uppercase ${isConnected ? 'text-success' : 'text-danger'}`}>
              {isConnected ? 'Link Active' : 'Link Lost'}
            </span>
          </div>
        </div>

        <div className="flex items-center gap-2 sm:gap-4">
          {activePlayerMeta}
          {headerControls}

          <button
            onClick={onToggleSettings}
            className="border-2 border-black bg-bg-primary p-1.5 hover:bg-accent hover:text-black transition-colors"
            title="Settings"
          >
            <Settings size={14} />
          </button>

          <button
            onClick={onPlayersClick}
            className="flex items-center gap-1.5 border-2 border-black bg-bg-primary px-2 py-1 text-[0.625rem] font-bold uppercase hover:bg-accent hover:text-black transition-colors"
          >
            <Users size={14} />
            <span className="hidden sm:inline">{playerCountLabel || playerCount}</span>
            <span className="sm:hidden">{playerCount}</span>
          </button>

          <button
            onClick={onLogout}
            className="border-2 border-black bg-bg-primary p-1.5 hover:bg-danger hover:text-black transition-colors"
            title="Log out"
          >
            <LogOut size={14} />
          </button>
        </div>
      </header>

      {/* Main Layout Area */}
      <div className="flex flex-1 min-h-0 flex-col md:flex-row">
        {/* Navigation Rail (Desktop Top / Mobile Bottom handled by NavigationRail internal logic) */}
        {!isMobile && <NavigationRail activeTab={activeTab} onTabChange={setActiveTab} />}

        <div className="flex flex-1 min-h-0 flex-col">
          {/* Breadcrumb & Global Filters */}
          <div className="shrink-0">
            <BreadcrumbNav stack={navStack} onNavigate={onNavigateBreadcrumb} />
            <GlobalFilterBar filters={filters} onRemoveFilter={onRemoveFilter} />
          </div>

          {/* Main Content */}
          <main className="flex-1 min-h-0 overflow-y-auto">
            {showSettings && settingsPanel && (
              <div className="sticky top-0 z-30 bg-bg-card border-b-2 border-black px-4 py-3 shadow-retro">
                {settingsPanel}
              </div>
            )}
            {children}
          </main>
        </div>
      </div>

      {/* Navigation Rail (Mobile Bottom) */}
      {isMobile && <NavigationRail activeTab={activeTab} onTabChange={setActiveTab} isMobile />}
    </div>
  );
};
