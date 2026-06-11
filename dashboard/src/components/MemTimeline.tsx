import React from 'react';
import { LineChart, Line, YAxis, ResponsiveContainer } from 'recharts';

interface MemTimelineProps {
  data: number[];
}

export const MemTimeline: React.FC<MemTimelineProps> = ({ data }) => {
  const chartData = data.map((v, i) => ({ val: v, i }));
  const maxMem = Math.max(...data, 128);
  const lastVal = data.length > 0 ? data[data.length - 1] : 0;

  // Detect spike (last val vs first in window)
  const isSpiking = data.length > 10 && lastVal > data[0] * 1.2;
  const strokeColor = isSpiking ? "#f85149" : "#d29922";

  return (
    <div className="h-24 w-full relative">
      <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={0}>
        <LineChart data={chartData}>
          <YAxis domain={[0, maxMem * 1.2]} hide />
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
        {lastVal.toFixed(1)} MB
      </div>
    </div>
  );
};
