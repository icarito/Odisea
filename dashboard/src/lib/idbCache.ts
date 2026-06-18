// Minimal IndexedDB key/value cache for the dashboard. No dependencies: a single
// object store keyed by string, holding arbitrary JSON-serialisable values plus
// a timestamp. Used for stale-while-revalidate: paint the last good payload from
// IDB instantly on load, then overwrite it once the live fetch resolves.
//
// Everything is best-effort — if IDB is unavailable (private mode, old browser)
// the helpers resolve to null/no-op so callers just fall back to the network.

const DB_NAME = 'odisea-dashboard';
const STORE = 'kv';
const DB_VERSION = 1;

interface CacheEntry<T> {
  value: T;
  savedAt: number; // unix ms
}

let dbPromise: Promise<IDBDatabase | null> | null = null;

function openDb(): Promise<IDBDatabase | null> {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve) => {
    if (typeof indexedDB === 'undefined') {
      resolve(null);
      return;
    }
    try {
      const req = indexedDB.open(DB_NAME, DB_VERSION);
      req.onupgradeneeded = () => {
        const db = req.result;
        if (!db.objectStoreNames.contains(STORE)) db.createObjectStore(STORE);
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => resolve(null);
    } catch {
      resolve(null);
    }
  });
  return dbPromise;
}

// Read a cached value (with its save time). Returns null when missing/unavailable.
export async function idbGet<T>(key: string): Promise<CacheEntry<T> | null> {
  const db = await openDb();
  if (!db) return null;
  return new Promise((resolve) => {
    try {
      const tx = db.transaction(STORE, 'readonly');
      const req = tx.objectStore(STORE).get(key);
      req.onsuccess = () => resolve((req.result as CacheEntry<T>) ?? null);
      req.onerror = () => resolve(null);
    } catch {
      resolve(null);
    }
  });
}

// Write a value under a key. Resolves once committed (or silently on failure).
export async function idbSet<T>(key: string, value: T): Promise<void> {
  const db = await openDb();
  if (!db) return;
  return new Promise((resolve) => {
    try {
      const tx = db.transaction(STORE, 'readwrite');
      tx.objectStore(STORE).put({ value, savedAt: Date.now() } as CacheEntry<T>, key);
      tx.oncomplete = () => resolve();
      tx.onerror = () => resolve();
      tx.onabort = () => resolve();
    } catch {
      resolve();
    }
  });
}

// Stable cache keys, centralised so callers can't drift apart.
export const CACHE_KEYS = {
  historicalSessions: 'historical-sessions',
  geoPlayers: 'geo-players',
} as const;
