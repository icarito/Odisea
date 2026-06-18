import React from 'react';
import { LayoutDashboard, Layers, Users, AreaChart, PlayCircle } from 'lucide-react';
import { Tab } from '../types';

interface NavigationRailProps {
  activeTab: Tab;
  onTabChange: (tab: Tab) => void;
  isMobile?: boolean;
}

export const NavigationRail: React.FC<NavigationRailProps> = ({ activeTab, onTabChange, isMobile }) => {
  const tabs: { id: Tab; label: string; icon: React.ReactNode }[] = [
    { id: 'dashboard', label: 'Dashboard', icon: <LayoutDashboard size={isMobile ? 24 : 20} /> },
    { id: 'scenes', label: 'Scenes', icon: <Layers size={isMobile ? 24 : 20} /> },
    { id: 'players', label: 'Players', icon: <Users size={isMobile ? 24 : 20} /> },
    { id: 'analysis', label: 'Analysis', icon: <AreaChart size={isMobile ? 24 : 20} /> },
    { id: 'replays', label: 'Replays', icon: <PlayCircle size={isMobile ? 24 : 20} /> },
  ];

  if (isMobile) {
    return (
      <nav className="fixed bottom-0 left-0 right-0 z-50 flex items-center justify-around border-t-4 border-black bg-bg-card px-2 pb-safe pt-2">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => onTabChange(tab.id)}
            className={`flex flex-col items-center gap-1 p-2 ${
              activeTab === tab.id ? 'text-accent' : 'text-text-muted'
            }`}
          >
            {tab.icon}
            <span className="text-[0.625rem] font-black uppercase tracking-tighter">{tab.label}</span>
          </button>
        ))}
      </nav>
    );
  }

  return (
    <nav className="flex items-center gap-1 border-b-2 border-black bg-bg-primary px-4 py-1">
      {tabs.map((tab) => (
        <button
          key={tab.id}
          onClick={() => onTabChange(tab.id)}
          className={`flex items-center gap-2 border-2 border-transparent px-4 py-1.5 transition-colors hover:bg-black/10 ${
            activeTab === tab.id
              ? 'border-b-accent bg-black/20 text-accent'
              : 'text-text-muted hover:text-text-primary'
          }`}
        >
          {tab.icon}
          <span className="text-xs font-black uppercase tracking-widest">{tab.label}</span>
        </button>
      ))}
    </nav>
  );
};
