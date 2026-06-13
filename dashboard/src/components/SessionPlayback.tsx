import React, { useMemo, useState, useEffect, useRef, useCallback } from 'react';
import {
  LineChart, Line, AreaChart, Area, XAxis, YAxis, CartesianGrid,
  Tooltip, ResponsiveContainer, ReferenceArea, ReferenceLine,
} from 'recharts';
import { Play, Pause, Square } from 'lucide-react';
import { sceneColor } from '../sceneColors';
import { RetroCard } from './retro';
import { Viewport3D } from './Viewport3D';
import { WARMUP_SECONDS, hasMemReport } from '../lib/filters';

interface Heartbeat {
  timestamp: number;
  fps: number;
  memory_mb: number;
  pos_x: number;
  pos_y: number;
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

const SPEEDS = [0.5, 1, 2, 4, 8] as const;

const fmtDuration = (s: number) => {
  if (!s || s < 0) return '0s';
  const m = Math.floor(s / 60);
  const sec = Math.round(s % 60);
  return m > 0 ? `${m}m ${sec}s` : `${sec}s`;
};

const fmtClock = (s: number) => {
  const safe = Math.max(0, s);
  const m = Math.floor(safe / 60);
  const sec = Math.floor(safe % 60);
  return `${m}:${sec.toString().padStart(2, '0')}`;
};

export const SessionPlayback: React.FC<SessionPlaybackProps> = ({ heartbeats, session }) => {
  const data = Array.isArray(heartbeats) ? heartbeats : [];

  const startTime = data[0]?.timestamp || 0;

  const chartData = useMemo(
    () => data.map((h, i) => ({
      time: Math.round((h.timestamp - startTime) * 10) / 10,
      fps: h.fps,
      mem: hasMemReport(h.memory_mb) ? h.memory_mb : null,
      scene: h.scene || '?',
      idx: i,
    })),
    [data, startTime]
  );

  const totalTime = chartData.length ? chartData[chartData.length - 1].time : 0;

  // --- transport state ---
  const [cursor, setCursor] = useState(0); // seconds from session start
  const [playing, setPlaying] = useState(false);
  const [speed, setSpeed] = useState<(typeof SPEEDS)[number]>(1);
  const lastFrameRef = useRef<number | null>(null);

  // Reset when a different session loads.
  useEffect(() => {
    setCursor(0);
    setPlaying(false);
  }, [session?.session_id, session?.player_id]);

  // Playback loop: advance the cursor by real elapsed time * speed.
  useEffect(() => {
    if (!playing) { lastFrameRef.current = null; return; }
    let raf = 0;
    const tick = (now: number) => {
      if (lastFrameRef.current != null) {
        const dt = (now - lastFrameRef.current) / 1000;
        setCursor((c) => {
          const next = c + dt * speed;
          if (next >= totalTime) { setPlaying(false); return totalTime; }
          return next;
        });
      }
      lastFrameRef.current = now;
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [playing, speed, totalTime]);

  const togglePlay = useCallback(() => {
    setPlaying((p) => {
      // Restart from 0 if we're at the end.
      if (!p && cursor >= totalTime) setCursor(0);
      return !p;
    });
  }, [cursor, totalTime]);

  const stop = useCallback(() => { setPlaying(false); setCursor(0); }, []);

  // Index of the last heartbeat at or before the cursor.
  const cursorIdx = useMemo(() => {
    if (chartData.length === 0) return 0;
    let idx = 0;
    for (let i = 0; i < chartData.length; i++) {
      if (chartData[i].time <= cursor) idx = i; else break;
    }
    return idx;
  }, [chartData, cursor]);

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

  // Derived session stats. Warmup (first WARMUP_SECONDS) is excluded from the
  // aggregates so the load spike doesn't skew avg/min FPS or memory — but the
  // full timeline stays scrubbable (a gray band marks the warmup window).
  const stats = useMemo(() => {
    const steady = data.filter((d) => (d.timestamp - startTime) >= WARMUP_SECONDS);
    const sample = steady.length ? steady : data;
    const fpsArr = sample.map(d => d.fps).filter(n => typeof n === 'number');
    const avgFps = session?.avg_fps ?? (fpsArr.reduce((a, b) => a + b, 0) / (fpsArr.length || 1));
    const minFps = fpsArr.length ? Math.min(...fpsArr) : 0;
    const lowPct = session?.low_fps_pct ?? (fpsArr.filter(f => f < 30).length * 100 / (fpsArr.length || 1));
    const memArr = sample.map(d => d.memory_mb).filter(hasMemReport);
    const avgMem = session?.avg_mem ?? (memArr.length ? memArr.reduce((a, b) => a + b, 0) / memArr.length : 0);
    const hasMem = memArr.length > 0;
    const duration = session?.duration ?? (data.length ? data[data.length - 1].timestamp - startTime : 0);
    return { avgFps, minFps, lowPct, avgMem, hasMem, duration };
  }, [data, session, startTime]);

  const platform = data[0]?.platform || session?.platform || '?';
  const engine = data[0]?.engine_version || '?';
  const location = [session?.city, session?.country_code || session?.country].filter(Boolean).join(', ');

  if (chartData.length === 0) {
    return (
      <RetroCard>
        <div className="text-center text-text-muted italic py-8 text-xs">
          SIN DATOS DE SESIÓN PARA REPRODUCIR
        </div>
      </RetroCard>
    );
  }

  const sceneTooltip = ({ active, payload }: any) => {
    if (!active || !payload?.length) return null;
    const d = payload[0].payload;
    return (
      <div className="bg-bg-primary border-2 border-black px-3 py-2 text-[0.625rem] font-mono shadow-[2px_2px_0px_0px_black]">
        <div className="font-black uppercase mb-1" style={{ color: sceneColor(d.scene) }}>{d.scene}</div>
        <div className="text-text-muted">t = {d.time}s</div>
        <div style={{ color: '#7fd1ff' }}>FPS: {d.fps?.toFixed?.(0) ?? d.fps}</div>
        <div style={{ color: '#eab308' }}>Mem: {d.mem != null ? `${d.mem.toFixed(1)} MB` : '—'}</div>
      </div>
    );
  };

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

  // Gray warmup band on both charts.
  const warmupBand = totalTime > 0 ? (
    <ReferenceArea x1={0} x2={Math.min(WARMUP_SECONDS, totalTime)} fill="#6b7280" fillOpacity={0.18} />
  ) : null;

  const cursorLine = (
    <ReferenceLine x={Math.round(cursor * 10) / 10} stroke="#f85149" strokeWidth={1.5} />
  );

  // Click a chart to seek.
  const onChartClick = (e: any) => {
    const t = e?.activeLabel;
    if (typeof t === 'number') { setCursor(t); setPlaying(false); }
  };

  // Cursor-driven 3D state: only the current heartbeat's position + the trail up
  // to the cursor, and only the current scene's geometry (no mixing).
  const cur = data[cursorIdx] || data[data.length - 1];
  const curScene = cur?.scene || session?.scene || '';
  // Trail limited to the contiguous run of the current scene up to the cursor,
  // so switching scenes doesn't draw a line across unrelated geometry.
  const trail = useMemo(() => {
    const pts: [number, number, number][] = [];
    for (let i = cursorIdx; i >= 0; i--) {
      if ((data[i].scene || '') !== (curScene || '')) break;
      pts.unshift([Number(data[i].pos_x) || 0, Number(data[i].pos_y) || 0, Number(data[i].pos_z) || 0]);
    }
    return pts;
  }, [data, cursorIdx, curScene]);

  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
      <div className="relative lg:col-span-2 h-96 min-h-[360px] overflow-hidden border-4 border-black shadow-retro">
        <Viewport3D
          position={[Number(cur.pos_x) || 0, Number(cur.pos_y) || 0, Number(cur.pos_z) || 0]}
          yaw={0}
          pitch={0}
          roll={0}
          trail={trail}
          follow={true}
          wireframe={false}
          sceneName={curScene}
          staleAge={0}
        />
        {/* Session identity overlay (key fields over the 3D view). */}
        <div className="pointer-events-none absolute top-3 left-3 max-w-[70%] border-2 border-black bg-bg-card/90 px-3 py-2 text-[0.625rem] font-mono shadow-[2px_2px_0px_0px_black]">
          <div className="mb-1 truncate font-black text-accent">{session?.display_name || session?.player_id || 'SESSION'}</div>
          {session?.display_name && (
            <div className="mb-1 truncate text-[0.5625rem] text-text-muted">{session.player_id}</div>
          )}
          <div className="grid grid-cols-[auto_minmax(0,1fr)] gap-x-2 gap-y-0.5 text-text-muted">
            <span>Scene</span><span className="truncate" style={{ color: sceneColor(curScene || '?') }}>{curScene || '—'}</span>
            <span>Platform</span><span className="uppercase text-text-primary">{platform}</span>
            <span>Engine</span><span className="truncate text-text-primary">{engine}</span>
            {location && <><span>Geo</span><span className="truncate text-text-primary">{location}</span></>}
            <span>Duration</span><span className="text-text-primary">{fmtDuration(stats.duration)}</span>
          </div>
        </div>
      </div>

      {/* Transport bar */}
      <div className="lg:col-span-2">
        <RetroCard>
          <div className="flex flex-col gap-3">
            <div className="flex items-center gap-3">
              <button
                onClick={togglePlay}
                className="flex h-10 w-10 shrink-0 items-center justify-center border-2 border-black bg-accent text-black hover:brightness-110"
                aria-label={playing ? 'Pause' : 'Play'}
              >
                {playing ? <Pause size={18} /> : <Play size={18} />}
              </button>
              <button
                onClick={stop}
                className="flex h-10 w-10 shrink-0 items-center justify-center border-2 border-black bg-bg-primary hover:bg-danger hover:text-black"
                aria-label="Stop"
              >
                <Square size={16} />
              </button>

              <input
                type="range"
                min={0}
                max={totalTime || 0}
                step={0.1}
                value={Math.min(cursor, totalTime)}
                onChange={(e) => { setCursor(Number(e.target.value)); setPlaying(false); }}
                className="flex-1 accent-accent"
                aria-label="Seek"
              />

              <span className="shrink-0 font-mono text-[0.625rem] text-text-muted tabular-nums">
                {fmtClock(cursor)} / {fmtClock(totalTime)}
              </span>
            </div>

            <div className="flex items-center gap-2">
              <span className="text-[0.625rem] uppercase font-black tracking-widest text-text-muted">Speed</span>
              <div className="flex border-2 border-black">
                {SPEEDS.map((s) => (
                  <button
                    key={s}
                    onClick={() => setSpeed(s)}
                    className={`px-2 py-1 text-[0.625rem] font-black ${speed === s ? 'bg-accent text-black' : 'bg-bg-primary text-text-muted'} ${s !== SPEEDS[0] ? 'border-l-2 border-black' : ''}`}
                  >
                    {s}x
                  </button>
                ))}
              </div>
              <span className="ml-auto font-mono text-[0.625rem]" style={{ color: sceneColor(curScene || '?') }}>
                {curScene || '—'}
              </span>
            </div>
          </div>
        </RetroCard>
      </div>

      {/* Scene legend strip (compact; the big Session Info card is gone — its
          fields now overlay the 3D view and the charts). */}
      <div className="lg:col-span-2 flex flex-wrap items-center gap-3 border-2 border-black bg-bg-card/50 px-3 py-2">
        {sceneOrder.map(s => (
          <span key={s} className="flex items-center gap-1.5 text-[0.625rem] font-mono uppercase">
            <span className="w-3 h-3 border-2 border-black" style={{ backgroundColor: sceneColor(s) }} />
            {s}
          </span>
        ))}
        <span className="flex items-center gap-1.5 text-[0.625rem] font-mono uppercase text-text-muted">
          <span className="w-3 h-3 border-2 border-black bg-[#6b7280]/40" />
          warmup ({WARMUP_SECONDS}s, excl. stats)
        </span>
      </div>

      <RetroCard title={
        <span className="flex w-full items-center justify-between gap-2">
          <span>FPS vs Time (s)</span>
          <span className="flex gap-2 text-[0.5625rem] normal-case">
            <span style={{ color: stats.avgFps > 55 ? '#3fb950' : stats.avgFps > 30 ? '#d29922' : '#f85149' }}>avg {stats.avgFps.toFixed(1)}</span>
            <span style={{ color: stats.minFps >= 30 ? '#3fb950' : '#f85149' }}>min {stats.minFps.toFixed(0)}</span>
            <span style={{ color: stats.lowPct < 10 ? '#3fb950' : stats.lowPct < 30 ? '#d29922' : '#f85149' }}>{stats.lowPct.toFixed(1)}% low</span>
          </span>
        </span>
      }>
        <div className="h-48 w-full">
          <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={0}>
            <LineChart data={chartData} onClick={onChartClick}>
              <CartesianGrid strokeDasharray="3 3" stroke="#232833" />
              {sceneBands}
              {warmupBand}
              {cursorLine}
              <XAxis dataKey="time" stroke="#666" fontSize={10} type="number" domain={['dataMin', 'dataMax']} />
              <YAxis stroke="#666" fontSize={10} domain={[0, 'auto']} />
              <Tooltip content={sceneTooltip} />
              <Line type="monotone" dataKey="fps" stroke="#7fd1ff" dot={false} strokeWidth={2} isAnimationActive={false} />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </RetroCard>

      <RetroCard title={
        <span className="flex w-full items-center justify-between gap-2">
          <span>Memory (MB)</span>
          <span className="text-[0.5625rem] normal-case text-[#eab308]">
            {stats.hasMem ? `avg ${stats.avgMem.toFixed(0)} MB` : 'sin datos'}
          </span>
        </span>
      }>
        <div className="h-48 w-full">
          {stats.hasMem ? (
            <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={0}>
              <AreaChart data={chartData} onClick={onChartClick}>
                <CartesianGrid strokeDasharray="3 3" stroke="#232833" />
                {sceneBands}
                {warmupBand}
                {cursorLine}
                <XAxis dataKey="time" stroke="#666" fontSize={10} type="number" domain={['dataMin', 'dataMax']} />
                <YAxis stroke="#666" fontSize={10} domain={[0, 'auto']} />
                <Tooltip content={sceneTooltip} />
                <Area type="monotone" dataKey="mem" stroke="#eab308" fill="#eab308" fillOpacity={0.2} connectNulls isAnimationActive={false} />
              </AreaChart>
            </ResponsiveContainer>
          ) : (
            <div className="flex h-full items-center justify-center text-[0.625rem] uppercase font-bold tracking-widest text-text-muted/60 italic">
              No memory report for this session
            </div>
          )}
        </div>
      </RetroCard>
    </div>
  );
};
