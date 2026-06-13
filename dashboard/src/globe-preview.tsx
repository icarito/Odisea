import { createRoot, type Root } from 'react-dom/client';
import { Globe3D } from './components/Globe3D/Globe3D';
import type { GeoPlayer } from './types';

const mock: GeoPlayer[] = [
  { player_id: 'a', session_id: 's', last_seen: Date.now() / 1000, country: 'Peru', country_code: 'PE', city: 'Lima', latitude: -12.05, longitude: -77.04, status: 'connected' },
  { player_id: 'b', session_id: 's', last_seen: Date.now() / 1000 - 600, country: 'Mexico', country_code: 'MX', city: 'CDMX', latitude: 19.43, longitude: -99.13, status: 'recent' },
  { player_id: 'c', session_id: 's', last_seen: Date.now() / 1000 - 100000, country: 'Spain', country_code: 'ES', city: 'Madrid', latitude: 40.41, longitude: -3.70, status: 'old' },
  { player_id: 'd', session_id: 's', last_seen: Date.now() / 1000, country: 'USA', country_code: 'US', city: 'NYC', latitude: 40.71, longitude: -74.0, status: 'connected' },
];

// HMR-safe: reuse a single root across hot reloads (avoids the double-createRoot warning).
const el = document.getElementById('root')!;
const g = globalThis as unknown as { __globeRoot?: Root };
const root = g.__globeRoot ?? (g.__globeRoot = createRoot(el));

root.render(
  <div style={{ position: 'relative', width: '100vw', height: '100vh', background: '#080a0f' }}>
    <Globe3D players={mock} />
  </div>,
);
