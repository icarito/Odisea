const DB_NAME = 'odisea_offline';
const DB_VERSION = 2;
const SNAPSHOT_STORE = 'snapshots';
const HEARTBEAT_STORE = 'heartbeat_samples';

export interface StoredHeartbeatSample {
  id: string;
  player_id: string;
  session_id: string;
  timestamp: number;
  scene: string;
  zone: string;
  mode: string;
  fps: number;
  memory_mb: number;
  position: [number, number, number];
  tick: number;
}

const openDB = (): Promise<IDBDatabase> => {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);
    request.onupgradeneeded = (event) => {
      const db = (event.target as IDBOpenDBRequest).result;
      if (!db.objectStoreNames.contains(SNAPSHOT_STORE)) {
        db.createObjectStore(SNAPSHOT_STORE);
      }
      if (!db.objectStoreNames.contains(HEARTBEAT_STORE)) {
        const store = db.createObjectStore(HEARTBEAT_STORE, { keyPath: 'id' });
        store.createIndex('timestamp', 'timestamp', { unique: false });
        store.createIndex('player_id', 'player_id', { unique: false });
        store.createIndex('session_id', 'session_id', { unique: false });
      }
    };
  });
};

const completeTx = (tx: IDBTransaction): Promise<boolean> => (
  new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve(true);
    tx.onerror = () => reject(tx.error);
  })
);

export const saveSnapshot = async (key: string, data: unknown) => {
  try {
    const db = await openDB();
    const tx = db.transaction(SNAPSHOT_STORE, 'readwrite');
    const store = tx.objectStore(SNAPSHOT_STORE);
    store.put(data, key);
    return completeTx(tx);
  } catch (e) {
    console.error('Failed to save snapshot to IndexedDB', e);
  }
};

export const getSnapshot = async <T = unknown>(key: string): Promise<T | null> => {
  try {
    const db = await openDB();
    const tx = db.transaction(SNAPSHOT_STORE, 'readonly');
    const store = tx.objectStore(SNAPSHOT_STORE);
    const request = store.get(key);
    return new Promise((resolve, reject) => {
      request.onsuccess = () => resolve((request.result as T | undefined) ?? null);
      request.onerror = () => reject(request.error);
    });
  } catch (e) {
    console.error('Failed to get snapshot from IndexedDB', e);
    return null;
  }
};

export const saveHeartbeatSamples = async (samples: StoredHeartbeatSample[]) => {
  if (samples.length === 0) return;
  try {
    const db = await openDB();
    const tx = db.transaction(HEARTBEAT_STORE, 'readwrite');
    const store = tx.objectStore(HEARTBEAT_STORE);
    samples.forEach((sample) => store.put(sample));
    return completeTx(tx);
  } catch (e) {
    console.error('Failed to save heartbeat samples to IndexedDB', e);
  }
};

export const getRecentHeartbeatSamples = async (
  sinceTimestamp: number,
  limit = 5000,
): Promise<StoredHeartbeatSample[]> => {
  try {
    const db = await openDB();
    const tx = db.transaction(HEARTBEAT_STORE, 'readonly');
    const store = tx.objectStore(HEARTBEAT_STORE);
    const index = store.index('timestamp');
    const request = index.getAll(IDBKeyRange.lowerBound(sinceTimestamp), limit);
    return new Promise((resolve, reject) => {
      request.onsuccess = () => resolve((request.result as StoredHeartbeatSample[]).sort((a, b) => a.timestamp - b.timestamp));
      request.onerror = () => reject(request.error);
    });
  } catch (e) {
    console.error('Failed to load heartbeat samples from IndexedDB', e);
    return [];
  }
};

export const pruneHeartbeatSamples = async (beforeTimestamp: number) => {
  try {
    const db = await openDB();
    const tx = db.transaction(HEARTBEAT_STORE, 'readwrite');
    const store = tx.objectStore(HEARTBEAT_STORE);
    const index = store.index('timestamp');
    const request = index.openCursor(IDBKeyRange.upperBound(beforeTimestamp));
    request.onsuccess = () => {
      const cursor = request.result;
      if (!cursor) return;
      cursor.delete();
      cursor.continue();
    };
    return completeTx(tx);
  } catch (e) {
    console.error('Failed to prune heartbeat samples from IndexedDB', e);
  }
};
