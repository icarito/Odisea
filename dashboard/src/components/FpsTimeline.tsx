import React from 'react';
import { LineChart, Line, YAxis, ResponsiveContainer, ReferenceLine } from 'recharts';

interface FpsTimelineProps {
  data: number[];
}

export const FpsTimeline: React.FC<FpsTimelineProps> = ({ data }) => {
  const chartData = data.map((v, i) => ({ val: v, i }));

  const lastVal = data.length > 0 ? data[data.length - 1] : 60;
  const strokeColor = lastVal > 55 ? "#3fb950" : (lastVal > 30 ? "#d29922" : "#f85149");

  return (
    <div className="h-24 w-full relative">
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={chartData}>
          <YAxis domain={[0, 120]} hide />
          <ReferenceLine y={30} stroke="#f85149" strokeDasharray="3 3" opacity={0.3} />
          <ReferenceLine y={60} stroke="#3fb950" strokeDasharray="3 3" opacity={0.3} />
          <Line
            type="monotone"
            dataKey="val"
            stroke={strokeColor}
            strokeWidth={1.5}
            dot={false}
            isAnimationActive={false}
          />
        </LineChart>
      </ResponsiveContainer>
      <div className="absolute top-0 right-0 text-[10px] font-bold" style={{ color: strokeColor }}>
        {lastVal.toFixed(0)} FPS
      </div>
    </div>
  );
};
