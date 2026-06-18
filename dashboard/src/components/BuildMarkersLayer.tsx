import React from 'react';
import { ReferenceLine } from 'recharts';

interface BuildMarkersLayerProps {
  builds: any[];
}

export const BuildMarkersLayer: React.FC<BuildMarkersLayerProps> = ({ builds }) => {
  return (
    <>
      {builds.map((build) => (
        <ReferenceLine
          key={build.id}
          x={build.timestamp}
          stroke="#d29922"
          strokeWidth={1}
          strokeDasharray="5 5"
          label={{ 
            value: build.version, 
            position: 'top', 
            fill: '#d29922', 
            fontSize: 9, 
            fontWeight: 'black' 
          }}
        />
      ))}
    </>
  );
};
