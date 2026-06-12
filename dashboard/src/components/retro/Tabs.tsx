import 'react';

interface Tab {
  id: string;
  label: string;
  icon?: React.ReactNode;
  disabled?: boolean;
}

interface TabsProps {
  tabs: Tab[];
  activeTab: string;
  onTabChange: (id: string) => void;
  className?: string;
}

export const RetroTabs: React.FC<TabsProps> = ({ tabs, activeTab, onTabChange, className = '' }) => {
  return (
    <div className={`retro-tabs-container ${className}`}>
      {tabs.map((tab) => (
        <button
          key={tab.id}
          onClick={() => !tab.disabled && onTabChange(tab.id)}
          disabled={tab.disabled}
          className={`retro-tab-btn flex flex-col sm:flex-row items-center justify-center gap-1 sm:gap-2 ${
            activeTab === tab.id ? 'retro-tab-btn-active' : ''
          } ${tab.disabled ? 'opacity-30 cursor-not-allowed grayscale' : ''}`}
        >
          <div>{tab.icon}</div>
          <span className="text-[0.5625rem] sm:text-[0.625rem] leading-none">{tab.label}</span>
        </button>
      ))}
    </div>
  );
};
