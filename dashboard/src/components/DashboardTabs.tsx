import React from 'react';
import { Activity, Globe } from 'lucide-react';

interface DashboardTabsProps {
  activeTab: string;
  onTabChange: (tab: string) => void;
}

const tabs = [
  { id: 'home', label: 'Home', icon: <Activity size={16} /> },
  { id: 'mapa', label: 'Mapa', icon: <Globe size={16} /> },
];

export const DashboardTabs: React.FC<DashboardTabsProps> = ({ activeTab, onTabChange }) => {
  return (
    <div className="flex border-b-2 border-black bg-bg-card">
      {tabs.map((tab) => (
        <button
          key={tab.id}
          onClick={() => onTabChange(tab.id)}
          className={`flex items-center gap-1.5 px-4 py-2 text-xs font-black uppercase transition-colors ${
            activeTab === tab.id
              ? 'bg-bg-primary text-accent border-b-2 border-accent -mb-[2px]'
              : 'text-text-muted hover:text-text-primary hover:bg-bg-primary/50'
          }`}
        >
          {tab.icon}
          {tab.label}
        </button>
      ))}
    </div>
  );
};
