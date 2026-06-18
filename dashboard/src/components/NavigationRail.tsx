import React from 'react';
import { LayoutDashboard, Box, Users, BarChart2, Video } from 'lucide-react';
import type { Tab } from '../types';

interface NavigationRailProps {
  activeTab: Tab;
  onTabChange: (tab: Tab) => void;
  className?: string;
  isMobile?: boolean;
}

const NAV_ITEMS: { id: Tab; label: string; icon: React.FC<any> }[] = [
  { id: 'dashboard', label: 'Cockpit', icon: LayoutDashboard },
  { id: 'scenes', label: 'Scenes', icon: Box },
  { id: 'players', label: 'Players', icon: Users },
  { id: 'analysis', label: 'Analysis', icon: BarChart2 },
  { id: 'replays', label: 'Replays', icon: Video },
];

export const NavigationRail: React.FC<NavigationRailProps> = ({ activeTab, onTabChange, className = '', isMobile = false }) => {
  if (isMobile) {
    return (
      <nav className={`fixed bottom-0 left-0 right-0 z-[100] border-t-4 border-black bg-bg-card flex justify-around py-1 ${className}`}>
        {NAV_ITEMS.map((item) => {
          const Icon = item.icon;
          const isActive = activeTab === item.id;
          return (
            <button
              key={item.id}
              onClick={() => onTabChange(item.id)}
              className={`flex flex-col items-center gap-1 p-2 min-w-[64px] ${isActive ? 'text-accent' : 'text-text-muted hover:text-text-primary'}`}
            >
              <Icon size={20} />
              <span className="text-[0.5rem] font-black uppercase tracking-tighter">{item.label}</span>
            </button>
          );
        })}
      </nav>
    );
  }

  return (
    <aside className={`flex w-20 flex-col items-center border-r-4 border-black bg-bg-card py-4 gap-6 ${className}`}>
      {NAV_ITEMS.map((item) => {
        const Icon = item.icon;
        const isActive = activeTab === item.id;
        return (
          <button
            key={item.id}
            onClick={() => onTabChange(item.id)}
            className={`group relative flex flex-col items-center gap-1 transition-colors ${isActive ? 'text-accent' : 'text-text-muted hover:text-text-primary'}`}
            title={item.label}
          >
            <div className={`p-2 border-2 transition-all ${isActive ? 'border-accent bg-accent/10 shadow-[2px_2px_0px_0px_black]' : 'border-transparent group-hover:border-black/20'}`}>
              <Icon size={24} />
            </div>
            <span className="text-[0.5rem] font-black uppercase tracking-widest">{item.label}</span>
            {isActive && (
              <div className="absolute -left-4 top-1/2 h-8 w-1 -translate-y-1/2 bg-accent" />
            )}
          </button>
        );
      })}
    </aside>
  );
};
