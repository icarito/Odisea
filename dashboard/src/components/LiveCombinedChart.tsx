import { useMemo } from 'react';
import {
  ComposedChart, Area, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend,
} from 'recharts';
import { hasMemReport } from '../lib/filters';

interface PlayerHistory {
  fps: number[];
  memory: number[];
}

// Combined FPS + Memory chart on a shared time axis with dual Y-axes: FPS as a
// line (left axis, 0..70), memory as an area (right axis, auto). Driven by the
// ring buffers useTelemetry keeps in history[pid]. Fills its parent's height.
export const LiveCombinedChart = ({ history }: { history?: PlayerHistory | null }) => {
  const data = useMemo(() => {
    const fps = history?.fps || [];
    const mem = history?.memory || [];
    const n = Math.max(fps.length, mem.length);
    return Array.from({ length: n }, (_, i) => ({
      t: i,
      fps: fps[i] ?? null,
      mem: hasMemReport(mem[i]) ? mem[i] : null,
    }));
  }, [history?.fps, history?.memory]);

  const hasMem = data.some((d) => d.mem != null);

  if (data.length === 0) {
    return (
      <div className="flex h-full items-center justify-center text-[0.625rem] uppercase font-bold tracking-widest text-text-muted/60 italic">
        Esperando datos en vivo…
      </div>
    );
  }

  const tooltip = ({ active, payload }: any) => {
    if (!active || !payload?.length) return null;
    const d = payload[0].payload;
    return (
      <div className="border-2 border-black bg-bg-primary px-3 py-2 text-[0.625rem] font-mono shadow-[2px_2px_0px_0px_black]">
        <div style={{ color: '#7fd1ff' }}>FPS: {d.fps != null ? Math.round(d.fps) : '—'}</div>
        <div style={{ color: '#3fb950' }}>Mem: {d.mem != null ? `${d.mem.toFixed(0)} MB` : '—'}</div>
      </div>
    );
  };

  return (
    <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={0}>
      <ComposedChart data={data} margin={{ top: 4, right: 8, bottom: 0, left: -8 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#232833" vertical={false} />
        <XAxis hide dataKey="t" />
        <YAxis
          yAxisId="fps"
          domain={[0, 70]}
          tick={{ fontSize: 9, fill: '#7fd1ff' }}
          axisLine={false}
          tickLine={false}
          width={28}
        />
        {hasMem && (
          <YAxis
            yAxisId="mem"
            orientation="right"
            domain={[0, 'auto']}
            tick={{ fontSize: 9, fill: '#3fb950' }}
            axisLine={false}
            tickLine={false}
            width={36}
          />
        )}
        <Tooltip content={tooltip} />
        <Legend
          verticalAlign="top"
          height={18}
          iconType="plainline"
          wrapperStyle={{ fontSize: '0.5625rem', textTransform: 'uppercase', fontFamily: 'monospace' }}
        />
        {hasMem && (
          <Area
            yAxisId="mem"
            name="Memory (MB)"
            type="monotone"
            dataKey="mem"
            stroke="#3fb950"
            strokeWidth={1.5}
            fill="#3fb950"
            fillOpacity={0.12}
            connectNulls
            isAnimationActive={false}
          />
        )}
        <Line
          yAxisId="fps"
          name="FPS"
          type="stepAfter"
          dataKey="fps"
          stroke="#7fd1ff"
          strokeWidth={2}
          dot={false}
          connectNulls
          isAnimationActive={false}
        />
      </ComposedChart>
    </ResponsiveContainer>
  );
};
