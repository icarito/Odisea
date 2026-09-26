import { useState, useEffect } from 'react';

const STORAGE_KEY = 'odisea_dashboard_layout';
const LAYOUT_VERSION = 3;
const DEFAULT_MIN_DURATION = 13;
// El historial estaba tapado por sesiones dev (181/200 en 36h); nightly+release
// por defecto, dev queda un click de distancia.
const DEFAULT_HISTORY_CHANNELS = ['nightly', 'release'];

export interface LayoutState {
  version: number;
  panelSizes: number[];
  activeTab: string;
  sidebarCollapsed: boolean;
  accelerometerEnabled: boolean;
  // Desktop filters sidebar collapsed state (docked column on xl+).
  filtersCollapsed: boolean;
  // History min-duration filter (seconds); excludes shorter sessions.
  historyMinDuration: number;
  // Canales de build visibles en History (chips Nightly/Release/Dev).
  historyChannels: string[];
}

const DEFAULT_STATE: LayoutState = {
  version: LAYOUT_VERSION,
  panelSizes: [20, 80],
  activeTab: 'live',
  sidebarCollapsed: false,
  accelerometerEnabled: false,
  filtersCollapsed: false,
  historyMinDuration: DEFAULT_MIN_DURATION,
  historyChannels: DEFAULT_HISTORY_CHANNELS,
};

export function useLayoutPersistence() {
  const [layout, setLayout] = useState<LayoutState>(() => {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) {
      try {
        const parsed = JSON.parse(saved);
        const next = { ...DEFAULT_STATE, ...parsed };
        if ((parsed.version || 1) < LAYOUT_VERSION) {
          next.version = LAYOUT_VERSION;
          next.historyMinDuration = DEFAULT_MIN_DURATION;
          next.historyChannels = DEFAULT_HISTORY_CHANNELS;
        }
        return next;
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
