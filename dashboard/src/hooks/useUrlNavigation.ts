import { useCallback, useEffect, useRef } from 'react';
import type { Tab } from '../types';

const VALID_TABS: Tab[] = ['live', 'mapa', 'heatmap', 'history'];
const ROOT_TAB: Tab = 'live';

export interface UrlNavState {
  tab: Tab;
  player: string | null;
}

const readUrl = (fallbackTab: Tab): UrlNavState => {
  const params = new URLSearchParams(window.location.search);
  const rawTab = params.get('tab');
  const tab = (rawTab && VALID_TABS.includes(rawTab as Tab)) ? (rawTab as Tab) : fallbackTab;
  const player = params.get('player');
  return { tab, player };
};

const buildSearch = (state: UrlNavState): string => {
  const params = new URLSearchParams(window.location.search);
  // Keep the root tab out of the URL so the home screen stays clean ("/").
  if (state.tab && state.tab !== ROOT_TAB) params.set('tab', state.tab);
  else params.delete('tab');
  if (state.player) params.set('player', state.player);
  else params.delete('player');
  const qs = params.toString();
  return qs ? `?${qs}` : '';
};

const sameState = (a: UrlNavState, b: UrlNavState) =>
  a.tab === b.tab && (a.player || null) === (b.player || null);

/**
 * Bridges the dashboard's tab + selected-player state with the browser URL and
 * history stack, so the back/forward buttons work as users expect.
 *
 * - `current` is the app's live view state (driven by React state).
 * - On change, we `pushState` a new history entry (unless it's the initial
 *   load or a popstate-driven restore, which use the existing entry).
 * - On `popstate` we read the URL back and call `onPopState` so the app can
 *   restore its state.
 *
 * The very first entry is the root (home) tab; in PWA standalone mode we keep a
 * guard so a back press from the root doesn't instantly exit the app — instead
 * it re-anchors at the root, matching native app behaviour.
 */
export function useUrlNavigation(
  current: UrlNavState,
  onPopState: (state: UrlNavState) => void,
) {
  const isPWA = useRef(window.matchMedia('(display-mode: standalone)').matches);
  // Guard re-entrancy: while we apply a popstate-driven restore we must not
  // push a new history entry in the sync effect below.
  const restoring = useRef(false);
  const lastApplied = useRef<UrlNavState>(current);

  // Seed the initial history entry from the current URL on mount.
  useEffect(() => {
    const initial = readUrl(current.tab);
    lastApplied.current = initial;
    window.history.replaceState({ navState: initial }, '');
    if (!sameState(initial, current)) {
      restoring.current = true;
      onPopState(initial);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Push a new history entry whenever the app's view state changes (and it
  // wasn't us restoring from a back/forward press).
  useEffect(() => {
    if (restoring.current) {
      restoring.current = false;
      lastApplied.current = current;
      return;
    }
    if (sameState(current, lastApplied.current)) return;
    lastApplied.current = current;
    const search = buildSearch(current);
    const url = `${window.location.pathname}${search}${window.location.hash}`;
    window.history.pushState({ navState: current }, '', url);
  }, [current]);

  // Restore state on back/forward. In PWA standalone mode, a back press that
  // would leave the app (no prior entry) re-anchors at the root instead.
  useEffect(() => {
    const onPop = (event: PopStateEvent) => {
      const restored = (event.state?.navState as UrlNavState | undefined) ?? readUrl(ROOT_TAB);

      if (isPWA.current && restored.tab === ROOT_TAB && !restored.player) {
        // At the root: keep the app from exiting by re-pushing the root entry,
        // but still apply the root state so any open selection closes.
        window.history.pushState({ navState: { tab: ROOT_TAB, player: null } }, '');
      }

      lastApplied.current = restored;
      restoring.current = true;
      onPopState(restored);
    };
    window.addEventListener('popstate', onPop);
    return () => window.removeEventListener('popstate', onPop);
  }, [onPopState]);

  // Imperative helper for callers that prefer to navigate explicitly.
  const navigate = useCallback((next: Partial<UrlNavState>) => {
    onPopState({ ...lastApplied.current, ...next });
  }, [onPopState]);

  return { navigate };
}
