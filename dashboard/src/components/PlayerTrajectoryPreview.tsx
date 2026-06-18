import React from 'react';
import { LineChart, Line, ResponsiveContainer } from 'recharts';

interface PlayerTrajectoryPreviewProps {
  trail: { pos_x: number; pos_z: number }[];
}

export const PlayerTrajectoryPreview: React.FC<PlayerTrajectoryPreviewProps> = ({ trail }) => {
  // Simple 2D projection of the trail for a spark-map
  return (
    <div className="h-full w-full border-2 border-black bg-black/40">
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={trail}>
          <Line 
            type="monotone" 
            dataKey="pos_z" 
            stroke="#7fd1ff" 
            strokeWidth={1.5} 
            dot={false} 
            isAnimationActive={false} 
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
};
