import React, { useEffect, useMemo, useState } from 'react';
import * as THREE from 'three';
import { feature } from 'topojson-client';
import type { Topology, GeometryCollection } from 'topojson-specification';

const RADIUS = 1.002;

function latLngToVec3(lat: number, lng: number): THREE.Vector3 {
  const phi = (90 - lat) * (Math.PI / 180);
  const theta = (lng + 180) * (Math.PI / 180);
  return new THREE.Vector3(
    -RADIUS * Math.sin(phi) * Math.cos(theta),
    RADIUS * Math.cos(phi),
    RADIUS * Math.sin(phi) * Math.sin(theta),
  );
}

export const CountryBorders: React.FC = () => {
  const [topo, setTopo] = useState<Topology | null>(null);

  useEffect(() => {
    fetch('https://cdn.jsdelivr.net/npm/world-atlas@2/countries-110m.json')
      .then(r => r.json())
      .then(setTopo)
      .catch(console.error);
  }, []);

  const geometry = useMemo(() => {
    if (!topo) return null;

    const countries = feature(topo, topo.objects.countries as GeometryCollection);
    const positions: number[] = [];

    const addRing = (coords: number[][]) => {
      for (let i = 0; i < coords.length - 1; i++) {
        const [lng1, lat1] = coords[i];
        const [lng2, lat2] = coords[i + 1];
        const v1 = latLngToVec3(lat1, lng1);
        const v2 = latLngToVec3(lat2, lng2);
        positions.push(v1.x, v1.y, v1.z, v2.x, v2.y, v2.z);
      }
    };

    countries.features.forEach(f => {
      if (!f.geometry) return;
      if (f.geometry.type === 'Polygon') {
        f.geometry.coordinates.forEach(ring => addRing(ring as number[][]));
      } else if (f.geometry.type === 'MultiPolygon') {
        f.geometry.coordinates.forEach(poly =>
          poly.forEach(ring => addRing(ring as number[][])),
        );
      }
    });

    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
    return geo;
  }, [topo]);

  if (!geometry) return null;

  return (
    <lineSegments geometry={geometry}>
      <lineBasicMaterial color="#1e4f8f" transparent opacity={0.6} />
    </lineSegments>
  );
};
