import React from 'react';
import { RetroTabs } from './retro';
import { Activity, Globe, Clock } from 'lucide-react';

interface DashboardTabsProps {
  activeTab: string;
  onTabChange: (tab: any) => void;
  playerCount: number;
}

export const DashboardTabs: React.FC<DashboardTabsProps> = ({ activeTab, onTabChange }) => {
  const tabs = [
    { id: 'live', label: 'Home', icon: <Activity size={20} /> },
    { id: 'mapa', label: 'Mapa', icon: <Globe size={20} /> },
    { id: 'history', label: 'Historial', icon: <Clock size={20} /> },
  ];

  return (
    <div className="flex border-b-2 border-black bg-bg-card">
      <RetroTabs 
        tabs={tabs} 
        activeTab={activeTab} 
        onTabChange={onTabChange} 
        className="flex-1"
      />
    </div>
  );
};
