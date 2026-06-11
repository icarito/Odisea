import React from 'react';
import { Activity, Map, Clock, Play, Users, LogOut } from 'lucide-react';
import { RetroTabs } from './retro';

interface DashboardLayoutProps {
  children: React.ReactNode;
  onLogout: () => void;
  isConnected: boolean;
  activeTab: string;
  setActiveTab: (tab: any) => void;
  playerCount: number;
  onPlayersClick: () => void;
  isSessionSelected: boolean;
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
  onPlayersClick,
  isSessionSelected,
}) => {
  const tabs = [
    { id: 'live', label: 'Live', icon: <Activity size={16} /> },
    { id: 'heatmap', label: 'Heatmap', icon: <Map size={16} /> },
    { id: 'history', label: 'History', icon: <Clock size={16} /> },
    { id: 'playback', label: 'Playback', icon: <Play size={16} />, disabled: !isSessionSelected },
  ];

  return (
    <div className="flex flex-col h-screen bg-bg-primary overflow-hidden font-mono crt-effect">
      {/* Fixed header */}
      <header className="shrink-0 flex items-center justify-between px-3 sm:px-4 py-2 border-b-4 border-black bg-bg-card z-30">
        <h1 className="text-accent font-black text-xs sm:text-base italic tracking-tighter">
          ODISEA<span className="hidden sm:inline"> CENTRAL</span><span className="sm:hidden">·V2</span>
        </h1>

        <div className="flex items-center gap-2 sm:gap-4">
          <span className="flex items-center gap-1.5 text-[0.625rem] uppercase font-bold">
            <span className={`w-2 h-2 rounded-full ${isConnected ? 'bg-success shadow-[0_0_8px_rgba(63,185,80,0.5)]' : 'bg-danger'}`} />
            <span className={isConnected ? 'text-success' : 'text-danger'}>{isConnected ? 'on' : 'off'}</span>
          </span>

          {/* Player count -> opens the bottom sheet */}
          <button
            onClick={onPlayersClick}
            className="flex items-center gap-1.5 px-2 py-1 border-2 border-black bg-bg-primary text-[0.625rem] font-bold uppercase hover:bg-accent hover:text-black transition-colors"
          >
            <Users size={14} />
            {playerCount} {playerCount === 1 ? 'player' : 'players'}
          </button>

          <button
            onClick={onLogout}
            className="p-1.5 border-2 border-black bg-bg-primary hover:bg-danger hover:text-black transition-colors"
            title="Log out"
          >
            <LogOut size={14} />
          </button>
        </div>
      </header>

      {/* Scrollable content */}
      <main className="flex-1 min-h-0 overflow-y-auto overflow-x-hidden">
        {children}
      </main>

      {/* Fixed bottom nav */}
      <nav className="shrink-0 border-t-4 border-black bg-bg-card z-30">
        <RetroTabs tabs={tabs} activeTab={activeTab} onTabChange={setActiveTab} />
      </nav>
    </div>
  );
};
