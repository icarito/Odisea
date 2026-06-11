import { useState, useEffect } from 'react';

const STORAGE_KEY = 'odisea_dashboard_layout';

export interface LayoutState {
  panelSizes: number[];
  activeTab: string;
  sidebarCollapsed: boolean;
  accelerometerEnabled: boolean;
}

const DEFAULT_STATE: LayoutState = {
  panelSizes: [20, 80],
  activeTab: 'live',
  sidebarCollapsed: false,
  accelerometerEnabled: false,
};

export function useLayoutPersistence() {
  const [layout, setLayout] = useState<LayoutState>(() => {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) {
      try {
        return { ...DEFAULT_STATE, ...JSON.parse(saved) };
      } catch (e) {
        return DEFAULT_STATE;
      }
    }
    return DEFAULT_STATE;
  });

  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(layout));
  }, [layout]);

  const updateLayout = (updates: Partial<LayoutState>) => {
    setLayout(prev => ({ ...prev, ...updates }));
  };

  return { layout, updateLayout };
}
