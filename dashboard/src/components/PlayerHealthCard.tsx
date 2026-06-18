import React, { useMemo } from 'react';
import { ResponsiveContainer, LineChart, Line, YAxis } from 'recharts';
import { Activity, Zap, Info } from 'lucide-react';

interface PlayerHealthCardProps {
  playerId: string;
  displayName?: string;
  fps: number;
  fpsHistory: number[];
  platform: string;
  scene: string;
  status: 'ok' | 'warning' | 'critical';
  targetFps?: number;
}

const PLATFORM_TARGETS: Record<string, number> = {
  'linux': 60,
  'windows': 60,
  'android': 30,
  'web': 60,
  'html5': 60,
};

export const PlayerHealthCard: React.FC<PlayerHealthCardProps> = ({
  fps,
  fpsHistory,
  platform,
  scene,
  status,
  targetFps,
}) => {
  const target = targetFps || PLATFORM_TARGETS[platform.toLowerCase()] || 60;
  
  const sparkData = useMemo(() => 
    fpsHistory.map((n, i) => ({ i, n })), 
  [fpsHistory]);

  const statusColor = {
    ok: 'text-success',
    warning: 'text-warning',
    critical: 'text-danger',
  }[status];

  const bgColor = {
    ok: 'bg-success/5',
    warning: 'bg-warning/5',
    critical: 'bg-danger/5',
  }[status];

  const borderColor = {
    ok: 'border-success/30',
    warning: 'border-warning/30',
    critical: 'border-danger/30',
  }[status];

  return (
    <div className={`flex flex-col gap-4 border-2 p-4 shadow-[2px_2px_0px_0px_black] transition-colors ${borderColor} ${bgColor}`}>
      <div className="flex items-start justify-between">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <Activity size={14} className={statusColor} />
            <span className="text-[0.625rem] font-black uppercase tracking-widest text-text-muted">Health Status</span>
          </div>
          <div className={`text-4xl font-black tracking-tighter ${statusColor}`}>
            {Math.round(fps)} <span className="text-sm font-bold uppercase tracking-normal opacity-50">FPS</span>
          </div>
        </div>
        <div className="text-right">
          <div className="text-[0.5rem] font-black uppercase tracking-widest text-text-muted mb-1">Target</div>
          <div className="border-2 border-black bg-bg-primary px-2 py-0.5 text-xs font-black">
            {target}
          </div>
        </div>
      </div>

      <div className="h-16 w-full border-b border-black/10 pb-2">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={sparkData}>
            <YAxis hide domain={[0, Math.max(target + 10, ...fpsHistory, 60)]} />
            <Line 
              type="monotone" 
              dataKey="n" 
              stroke={status === 'ok' ? '#3fb950' : status === 'warning' ? '#d29922' : '#f85149'} 
              dot={false} 
              strokeWidth={2} 
              isAnimationActive={false} 
            />
          </LineChart>
        </ResponsiveContainer>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div className="flex flex-col gap-1">
          <div className="flex items-center gap-1 text-[0.5rem] font-black uppercase text-text-muted">
            <Zap size={10} />
            Platform
          </div>
          <div className="truncate text-[0.625rem] font-bold uppercase">{platform}</div>
        </div>
        <div className="flex flex-col gap-1">
          <div className="flex items-center gap-1 text-[0.5rem] font-black uppercase text-text-muted">
            <Info size={10} />
            Scene
          </div>
          <div className="truncate text-[0.625rem] font-bold uppercase text-accent">{scene}</div>
        </div>
      </div>
    </div>
  );
};
