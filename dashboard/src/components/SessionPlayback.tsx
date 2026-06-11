import React, { useMemo, useRef, useEffect, useState } from 'react';
import {
  LineChart, Line, AreaChart, Area, XAxis, YAxis, CartesianGrid,
  Tooltip, ResponsiveContainer, ReferenceArea,
} from 'recharts';
import { sceneColor } from '../sceneColors';

interface Heartbeat {
  timestamp: number;
  fps: number;
  memory_mb: number;
  pos_x: number;
  pos_z: number;
  scene?: string;
  platform?: string;
  engine_version?: string;
}

interface SessionPlaybackProps {
  heartbeats: Heartbeat[];
  session?: any;
}

interface SceneSegment {
  scene: string;
  startTime: number; // seconds from session start
  endTime: number;
  startIdx: number;
  endIdx: number;
}

const fmtDuration = (s: number) => {
  if (!s || s < 0) return '0s';
  const m = Math.floor(s / 60);
  const sec = Math.round(s % 60);
  return m > 0 ? `${m}m ${sec}s` : `${sec}s`;
};

const Stat: React.FC<{ label: string; value: React.ReactNode; color?: string }> = ({ label, value, color }) => (
  <div className="flex flex-col">
    <span className="text-[10px] uppercase text-[#666] font-bold">{label}</span>
    <span className="text-sm font-mono" style={color ? { color } : undefined}>{value}</span>
  </div>
);

export const SessionPlayback: React.FC<SessionPlaybackProps> = ({ heartbeats, session }) => {
  const data = Array.isArray(heartbeats) ? heartbeats : [];
  const [hoverIdx, setHoverIdx] = useState<number | null>(null);

  const startTime = data[0]?.timestamp || 0;

  const chartData = useMemo(
    () => data.map((h, i) => ({
      time: Math.round((h.timestamp - startTime) * 10) / 10,
      fps: h.fps,
      mem: h.memory_mb,
      scene: h.scene || '?',
      idx: i,
    })),
    [data, startTime]
  );

  // Build contiguous scene segments for the reference bands + trail coloring.
  const segments = useMemo<SceneSegment[]>(() => {
    const segs: SceneSegment[] = [];
    chartData.forEach((d, i) => {
      const last = segs[segs.length - 1];
      if (last && last.scene === d.scene) {
        last.endTime = d.time;
        last.endIdx = i;
      } else {
        segs.push({ scene: d.scene, startTime: d.time, endTime: d.time, startIdx: i, endIdx: i });
      }
    });
    return segs;
  }, [chartData]);

  // Distinct scenes in visit order, for the legend.
  const sceneOrder = useMemo(() => {
    const seen: string[] = [];
    segments.forEach(s => { if (!seen.includes(s.scene)) seen.push(s.scene); });
    return seen;
  }, [segments]);

  // Derived session stats (prefer the session summary, fall back to the data).
  const stats = useMemo(() => {
    const fpsArr = data.map(d => d.fps).filter(n => typeof n === 'number');
    const avgFps = session?.avg_fps ?? (fpsArr.reduce((a, b) => a + b, 0) / (fpsArr.length || 1));
    const minFps = fpsArr.length ? Math.min(...fpsArr) : 0;
    const lowPct = session?.low_fps_pct ?? (fpsArr.filter(f => f < 30).length * 100 / (fpsArr.length || 1));
    const avgMem = session?.avg_mem ?? (data.reduce((a, b) => a + (b.memory_mb || 0), 0) / (data.length || 1));
    const duration = session?.duration ?? (data.length ? data[data.length - 1].timestamp - startTime : 0);
    return { avgFps, minFps, lowPct, avgMem, duration };
  }, [data, session, startTime]);

  const platform = data[0]?.platform || session?.platform || '?';
  const engine = data[0]?.engine_version || '?';

  const renderTrail = (canvas: HTMLCanvasElement | null) => {
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    const { width, height } = canvas;
    ctx.clearRect(0, 0, width, height);
    if (data.length < 2) return;

    let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
    data.forEach(h => {
      minX = Math.min(minX, h.pos_x); maxX = Math.max(maxX, h.pos_x);
      minZ = Math.min(minZ, h.pos_z); maxZ = Math.max(maxZ, h.pos_z);
    });

    const pad = 24;
    const rangeX = (maxX - minX) || 1;
    const rangeZ = (maxZ - minZ) || 1;
    const scale = Math.min((width - pad * 2) / rangeX, (height - pad * 2) / rangeZ);
    const toX = (x: number) => pad + (x - minX) * scale;
    const toZ = (z: number) => pad + (z - minZ) * scale;

    // One stroke per scene segment, colored by scene.
    ctx.lineWidth = 2;
    segments.forEach(seg => {
      ctx.strokeStyle = sceneColor(seg.scene);
      ctx.beginPath();
      // include the previous point so segments connect visually
      const from = Math.max(0, seg.startIdx - 1);
      ctx.moveTo(toX(data[from].pos_x), toZ(data[from].pos_z));
      for (let i = seg.startIdx; i <= seg.endIdx; i++) {
        ctx.lineTo(toX(data[i].pos_x), toZ(data[i].pos_z));
      }
      ctx.stroke();
    });

    // Start (green) / End (red) markers.
    ctx.fillStyle = '#22c55e';
    ctx.beginPath(); ctx.arc(toX(data[0].pos_x), toZ(data[0].pos_z), 5, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#ef4444';
    ctx.beginPath(); ctx.arc(toX(data[data.length - 1].pos_x), toZ(data[data.length - 1].pos_z), 5, 0, Math.PI * 2); ctx.fill();

    // Synced hover marker from the charts.
    if (hoverIdx != null && data[hoverIdx]) {
      const h = data[hoverIdx];
      ctx.fillStyle = '#ffffff';
      ctx.strokeStyle = sceneColor(h.scene);
      ctx.lineWidth = 3;
      ctx.beginPath(); ctx.arc(toX(h.pos_x), toZ(h.pos_z), 6, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
    }
  };

  // Redraw the canvas when hover or data changes (canvas ref callback only fires on mount).
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  useEffect(() => { renderTrail(canvasRef.current); });

  if (chartData.length === 0) {
    return (
      <div className="bg-[#161a22] p-8 rounded-lg border border-[#232833] text-center text-[#666] text-sm">
        Sin datos de sesión para reproducir.
      </div>
    );
  }

  const sceneTooltip = ({ active, payload }: any) => {
    if (!active || !payload?.length) return null;
    const d = payload[0].payload;
    return (
      <div className="bg-[#0c0e12] border border-[#232833] rounded px-3 py-2 text-[11px] font-mono">
        <div className="font-bold mb-1" style={{ color: sceneColor(d.scene) }}>{d.scene}</div>
        <div className="text-[#999]">t = {d.time}s</div>
        <div style={{ color: '#7fd1ff' }}>FPS: {d.fps?.toFixed?.(0) ?? d.fps}</div>
        <div style={{ color: '#eab308' }}>Mem: {d.mem?.toFixed?.(1) ?? d.mem} MB</div>
      </div>
    );
  };

  // Sync hover index out of recharts to the trail.
  const onChartMove = (state: any) => {
    const i = state?.activePayload?.[0]?.payload?.idx;
    setHoverIdx(typeof i === 'number' ? i : null);
  };
  const onChartLeave = () => setHoverIdx(null);

  const sceneBands = segments.map((seg, i) => (
    <ReferenceArea
      key={i}
      x1={seg.startTime}
      x2={seg.endTime}
      fill={sceneColor(seg.scene)}
      fillOpacity={0.08}
      stroke={sceneColor(seg.scene)}
      strokeOpacity={0.15}
    />
  ));

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
      {/* Session info card */}
      <div className="bg-[#161a22] p-4 rounded-lg border border-[#232833] lg:col-span-2">
        <div className="flex items-center justify-between flex-wrap gap-2 mb-3">
          <h3 className="text-[#7fd1ff] text-xs font-bold uppercase">Session Info</h3>
          <span className="text-[10px] font-mono text-[#666]">{session?.player_id}</span>
        </div>
        <div className="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-7 gap-4">
          <Stat label="Platform" value={platform} />
          <Stat label="Engine" value={engine} />
          <Stat label="Duration" value={fmtDuration(stats.duration)} />
          <Stat label="Avg FPS" value={stats.avgFps.toFixed(1)}
            color={stats.avgFps > 55 ? '#3fb950' : stats.avgFps > 30 ? '#d29922' : '#f85149'} />
          <Stat label="Min FPS" value={stats.minFps.toFixed(0)}
            color={stats.minFps >= 30 ? '#3fb950' : '#f85149'} />
          <Stat label="% Low FPS" value={`${stats.lowPct.toFixed(1)}%`}
            color={stats.lowPct < 10 ? '#3fb950' : stats.lowPct < 30 ? '#d29922' : '#f85149'} />
          <Stat label="Avg Mem" value={`${stats.avgMem.toFixed(0)} MB`} />
        </div>
        {/* Scene legend */}
        <div className="flex flex-wrap gap-3 mt-4 pt-3 border-t border-[#232833]">
          {sceneOrder.map(s => (
            <span key={s} className="flex items-center gap-1.5 text-[11px]">
              <span className="w-3 h-3 rounded-sm" style={{ backgroundColor: sceneColor(s) }} />
              {s}
            </span>
          ))}
        </div>
      </div>

      <div className="bg-[#161a22] p-4 rounded-lg border border-[#232833]">
        <h3 className="text-[#7fd1ff] text-xs font-bold mb-4 uppercase">FPS vs Time (s)</h3>
        <div className="h-48 w-full">
          <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={0}>
            <LineChart data={chartData} onMouseMove={onChartMove} onMouseLeave={onChartLeave}>
              <CartesianGrid strokeDasharray="3 3" stroke="#232833" />
              {sceneBands}
              <XAxis dataKey="time" stroke="#666" fontSize={10} type="number" domain={['dataMin', 'dataMax']} />
              <YAxis stroke="#666" fontSize={10} domain={[0, 'auto']} />
              <Tooltip content={sceneTooltip} />
              <Line type="monotone" dataKey="fps" stroke="#7fd1ff" dot={false} strokeWidth={2} isAnimationActive={false} />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </div>

      <div className="bg-[#161a22] p-4 rounded-lg border border-[#232833]">
        <h3 className="text-[#7fd1ff] text-xs font-bold mb-4 uppercase">Memory (MB)</h3>
        <div className="h-48 w-full">
          <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={0}>
            <AreaChart data={chartData} onMouseMove={onChartMove} onMouseLeave={onChartLeave}>
              <CartesianGrid strokeDasharray="3 3" stroke="#232833" />
              {sceneBands}
              <XAxis dataKey="time" stroke="#666" fontSize={10} type="number" domain={['dataMin', 'dataMax']} />
              <YAxis stroke="#666" fontSize={10} domain={[0, 'auto']} />
              <Tooltip content={sceneTooltip} />
              <Area type="monotone" dataKey="mem" stroke="#eab308" fill="#eab308" fillOpacity={0.2} isAnimationActive={false} />
            </AreaChart>
          </ResponsiveContainer>
        </div>
      </div>

      <div className="bg-[#161a22] p-4 rounded-lg border border-[#232833] lg:col-span-2">
        <h3 className="text-[#7fd1ff] text-xs font-bold mb-4 uppercase">Movement Trail (Bird's Eye)</h3>
        <div className="flex justify-center bg-[#0c0e12] rounded border border-[#232833] p-2">
          <canvas
            ref={canvasRef}
            width={800}
            height={300}
            className="max-w-full h-auto"
          />
        </div>
      </div>
    </div>
  );
};
