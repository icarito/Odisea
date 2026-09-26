import { useMemo } from 'react';
import {
  ComposedChart, Area, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend, ReferenceLine,
} from 'recharts';
import { hasMemReport, formatSeconds } from '../lib/filters';
import { EVENT_COLORS, eventTimeMs, normalizeEventType } from './EventTimeline';
import type { TelemetryEvent } from '../types';

interface PlayerHistory {
  fps: number[];
  memory: number[];
}

interface LiveCombinedChartProps {
  history?: PlayerHistory | null;
  // Marcadores de eventos en vivo (misma paleta/estilo que SessionPlayback).
  // El eje X es un indice de muestra sin timestamp, asi que el evento mas
  // reciente se ancla a la ultima muestra y el resto se separa por timestamp.
  events?: TelemetryEvent[];
  sampleIntervalMs?: number;
}

const markerLabel = (type: string, data: Record<string, any>): string => {
  if (type === 'scene_change') {
    const scene = String(data.to || '');
    const load = Number(data.load_ms);
    return [scene, Number.isFinite(load) && load > 0 ? formatSeconds(load) : ''].filter(Boolean).join(' · ');
  }
  if (type === 'death') return '☠';
  return '';
};

// Combined FPS + Memory chart on a shared time axis with dual Y-axes: FPS as a
// line (left axis, 0..70), memory as an area (right axis, auto). Driven by the
// ring buffers useTelemetry keeps in history[pid]. Fills its parent's height.
export const LiveCombinedChart = ({ history, events, sampleIntervalMs = 100 }: LiveCombinedChartProps) => {
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

  const markers = useMemo(() => {
    const n = data.length;
    if (n === 0) return [];
    const evs = (events || [])
      .map((ev) => ({
        type: normalizeEventType(String(ev.type || '')),
        ms: eventTimeMs(ev.timestamp),
        data: (ev.data || {}) as Record<string, any>,
      }))
      .filter((ev) => ev.ms > 0)
      .sort((a, b) => a.ms - b.ms);
    if (evs.length === 0) return [];
    const newest = evs[evs.length - 1].ms;
    const interval = Math.max(1, sampleIntervalMs);
    return evs
      .map((ev) => {
        const index = (n - 1) - Math.round((newest - ev.ms) / interval);
        return { ms: ev.ms, index, color: EVENT_COLORS[ev.type] || '#8b949e', label: markerLabel(ev.type, ev.data) };
      })
      .filter((m) => m.index >= 0 && m.index < n);
  }, [events, data, sampleIntervalMs]);

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
        {markers.map((m) => (
          <ReferenceLine
            key={`${m.ms}-${m.index}`}
            x={m.index}
            yAxisId="fps"
            stroke={m.color}
            strokeWidth={1}
            strokeDasharray="3 3"
            label={m.label ? { value: m.label, position: 'top', fill: m.color, fontSize: 8 } : undefined}
          />
        ))}
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
