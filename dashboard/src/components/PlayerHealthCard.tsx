import React from 'react';
import { LineChart, Line, ResponsiveContainer, YAxis } from 'recharts';

interface PlayerHealthCardProps {
  fps: number;
  history: { fps: number }[];
  platform: string;
  target?: number;
}

export const PlayerHealthCard: React.FC<PlayerHealthCardProps> = ({ fps, history, platform, target = 60 }) => {
  const getStatus = (val: number) => {
    if (val < 30) return 'critical';
    if (val < 45) return 'warning';
    return 'ok';
  };

  const status = getStatus(fps);
  const colorMap = {
    ok: 'text-success',
    warning: 'text-warning',
    critical: 'text-danger'
  };

  const sparkData = history.map((h, i) => ({ i, fps: h.fps }));

  return (
    <div className="flex items-center justify-between border-2 border-black bg-bg-card p-2 shadow-[2px_2px_0px_0px_black]">
      <div className="flex flex-col">
        <div className="flex items-baseline gap-1">
          <span className={`text-2xl font-black tabular-nums leading-none ${colorMap[status]}`}>
            {Math.round(fps)}
          </span>
          <span className="text-[0.5rem] font-bold uppercase text-text-muted">fps</span>
        </div>
        <div className="text-[0.5rem] font-bold uppercase tracking-tighter text-text-muted">
          Target: {target} · {platform}
        </div>
      </div>
      
      <div className="h-8 w-16">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={sparkData}>
            <YAxis domain={[0, 70]} hide />
            <Line 
              type="monotone" 
              dataKey="fps" 
              stroke="currentColor" 
              className={colorMap[status]}
              strokeWidth={2} 
              dot={false} 
              isAnimationActive={false} 
            />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
};
