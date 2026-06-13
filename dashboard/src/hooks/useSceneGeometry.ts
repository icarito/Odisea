import { useState, useEffect } from 'react';

export interface SceneBounds {
  min: [number, number, number];
  max: [number, number, number];
}

export interface SceneZone {
  name: string;
  position: [number, number, number];
  bounds: SceneBounds;
  type: string;
}

export interface SceneProp {
  name: string;
  position: [number, number, number];
  type: 'prop' | 'rotator';
  tags: string[];
  radius?: number;
}

export interface SceneGeometryData {
  scene: string;
  version: number;
  bounds: SceneBounds;
  points: [number, number, number][];
  zones: SceneZone[];
  props: SceneProp[];
  metadata: {
    generated_at: string;
    point_count: number;
    zone_count: number;
    prop_count: number;
  };
  stream?: {
    center: [number, number, number];
    radius: number;
    limit: number;
    returned_points: number;
    total_points: number;
    truncated: boolean;
  };
}

const geometryCache: Record<string, SceneGeometryData> = {};

export const useSceneGeometry = (sceneName: string) => {
  const [geometry, setGeometry] = useState<SceneGeometryData | null>(
    sceneName ? geometryCache[sceneName] || null : null
  );
  const [loading, setLoading] = useState<boolean>(!!sceneName && !geometryCache[sceneName]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!sceneName) {
      setGeometry(null);
      setLoading(false);
      return;
    }

    if (geometryCache[sceneName]) {
      setGeometry(geometryCache[sceneName]);
      setLoading(false);
      return;
    }

    let aborted = false;
    const fetchGeometry = async () => {
      setLoading(true);
      setError(null);
      try {
        const response = await fetch(`/scene-data/${sceneName}.json`);
        if (!response.ok) {
          throw new Error(`Failed to load geometry for ${sceneName}: ${response.statusText}`);
        }
        const data: SceneGeometryData = await response.json();
        if (!aborted) {
          geometryCache[sceneName] = data;
          setGeometry(data);
        }
      } catch (err: unknown) {
        if (!aborted) {
          const message = err instanceof Error ? err.message : String(err);
          console.warn(`Scene geometry loading failed for ${sceneName}`, err);
          setError(message);
        }
      } finally {
        if (!aborted) {
          setLoading(false);
        }
      }
    };

    fetchGeometry();

    return () => {
      aborted = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sceneName]);

  return { geometry, loading, error };
};

const streamCache: Record<string, SceneGeometryData> = {};

const bucketCoord = (value: number, size: number) => Math.floor(value / size) * size;

export const useSceneGeometryStream = (
  sceneName: string,
  center: [number, number, number],
  radius = 160,
  limit = 30000
) => {
  const bucketSize = Math.max(20, radius * 0.5);
  const bucket: [number, number, number] = [
    bucketCoord(center[0], bucketSize),
    bucketCoord(center[1], bucketSize),
    bucketCoord(center[2], bucketSize),
  ];
  const cacheKey = sceneName
    ? `${sceneName}:${bucket.join(',')}:${radius}:${limit}`
    : '';
  const [geometry, setGeometry] = useState<SceneGeometryData | null>(
    cacheKey ? streamCache[cacheKey] || null : null
  );
  const [loading, setLoading] = useState<boolean>(!!cacheKey && !streamCache[cacheKey]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!sceneName) {
      setGeometry(null);
      setLoading(false);
      return;
    }

    if (streamCache[cacheKey]) {
      setGeometry(streamCache[cacheKey]);
      setLoading(false);
      return;
    }

    setGeometry(null);
    let aborted = false;
    const fetchGeometry = async () => {
      setLoading(true);
      setError(null);
      try {
        const params = new URLSearchParams({
          x: String(bucket[0]),
          y: String(bucket[1]),
          z: String(bucket[2]),
          radius: String(radius),
          limit: String(limit),
        });
        const response = await fetch(`/api/scene-data/${encodeURIComponent(sceneName)}?${params.toString()}`);
        if (!response.ok) {
          throw new Error(`Failed to stream geometry for ${sceneName}: ${response.statusText}`);
        }
        const data: SceneGeometryData = await response.json();
        if (!aborted) {
          streamCache[cacheKey] = data;
          setGeometry(data);
        }
      } catch (err: unknown) {
        if (!aborted) {
          const message = err instanceof Error ? err.message : String(err);
          console.warn(`Scene geometry stream failed for ${sceneName}`, err);
          setError(message);
        }
      } finally {
        if (!aborted) {
          setLoading(false);
        }
      }
    };

    fetchGeometry();

    return () => {
      aborted = true;
    };
  }, [cacheKey, sceneName, bucket[0], bucket[1], bucket[2], radius, limit]);

  return { geometry, loading, error };
};
