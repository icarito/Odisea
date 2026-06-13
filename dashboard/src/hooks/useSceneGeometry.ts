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
