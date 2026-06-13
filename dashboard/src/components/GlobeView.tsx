import React, { useMemo } from 'react';
import {
  ComposableMap,
  Geographies,
  Geography,
  Marker,
} from 'react-simple-maps';

// Light-weight world geojson URL
const geoUrl = "https://cdn.jsdelivr.net/npm/world-atlas@2/countries-110m.json";

interface GeoPlayer {
  player_id: string;
  session_id: string;
  last_seen: number;
  country: string;
  country_code: string;
  city: string;
  latitude: number;
  longitude: number;
  display_name?: string;
  color?: string;
  status: 'connected' | 'recent' | 'old';
}

interface GlobeViewProps {
  players: GeoPlayer[];
}

export const GlobeView: React.FC<GlobeViewProps> = ({ players }) => {
  const statusColor = (status: string, customColor?: string) => {
    if (status === 'connected') return customColor || '#3fb950';
    if (status === 'recent') return '#d29922';
    return '#8b949e';
  };

  const groupedMarkers = useMemo(() => {
    const groups: { [key: string]: { 
      lat: number, 
      lng: number, 
      count: number, 
      city: string, 
      country: string, 
      names: string[],
      status: 'connected' | 'recent' | 'old'
    } } = {};

    players.forEach(p => {
      const key = `${p.latitude.toFixed(2)}|${p.longitude.toFixed(2)}`;
      if (!groups[key]) {
        groups[key] = {
          lat: p.latitude,
          lng: p.longitude,
          count: 0,
          city: p.city,
          country: p.country,
          names: [],
          status: 'old'
        };
      }
      groups[key].count++;
      if (p.display_name) groups[key].names.push(p.display_name);
      
      // Upgrade group status
      if (p.status === 'connected') groups[key].status = 'connected';
      else if (p.status === 'recent' && groups[key].status === 'old') groups[key].status = 'recent';
    });

    return Object.values(groups);
  }, [players]);

  return (
    <div className="h-full w-full bg-[#0d1117] flex flex-col p-4">
      <div className="mb-4 flex items-center justify-between">
        <div>
          <h2 className="text-xl font-black italic text-accent uppercase tracking-tighter">Globe Heatmap</h2>
          <p className="text-[0.625rem] text-text-muted uppercase">Distribución geográfica de jugadores</p>
        </div>
        <div className="flex gap-4 text-[0.625rem] font-bold uppercase">
          <div className="flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full bg-success" /> Conectado
          </div>
          <div className="flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full bg-[#888]" /> Última hora
          </div>
          <div className="flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full bg-danger" /> {'>'}1h
          </div>
        </div>
      </div>

      <div className="flex-1 border-4 border-black bg-black/40 relative overflow-hidden">
        <ComposableMap projectionConfig={{ scale: 200 }}>
          <Geographies geography={geoUrl}>
            {({ geographies }) =>
              geographies.map((geo) => (
                <Geography
                  key={geo.rgsid || geo.properties.name}
                  geography={geo}
                  fill="#161b22"
                  stroke="#30363d"
                  strokeWidth={0.5}
                  style={{
                    default: { outline: "none" },
                    hover: { fill: "#1f242b", outline: "none" },
                    pressed: { outline: "none" },
                  }}
                />
              ))
            }
          </Geographies>
          {groupedMarkers.map((marker, i) => (
            <Marker key={i} coordinates={[marker.lng, marker.lat]}>
              <circle
                r={4 + Math.min(marker.count * 2, 20)}
                fill={statusColor(marker.status)}
                stroke="#c9d1d9"
                strokeWidth={marker.status === 'connected' ? 1 : 0.5}
                className={marker.status === 'connected' ? 'animate-pulse' : ''}
                opacity={0.85}
              >
                <title>
                  {marker.city}, {marker.country}
                  {"\n"}Players: {marker.count}
                  {marker.names.length > 0 ? `\nTags: ${marker.names.join(", ")}` : ""}
                </title>
              </circle>
            </Marker>
          ))}
        </ComposableMap>
      </div>
    </div>
  );
};
