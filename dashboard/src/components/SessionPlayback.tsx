import React from 'react';
import { LineChart, Line, AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';

interface Heartbeat {
  timestamp: number;
  fps: number;
  memory_mb: number;
  pos_x: number;
  pos_z: number;
}

interface SessionPlaybackProps {
  heartbeats: Heartbeat[];
}

export const SessionPlayback: React.FC<SessionPlaybackProps> = ({ heartbeats }) => {
  const startTime = heartbeats[0]?.timestamp || 0;
  const chartData = heartbeats.map(h => ({
    time: Math.round(h.timestamp - startTime),
    fps: h.fps,
    mem: h.memory_mb
  }));

  // Simple trail map using canvas
  const renderTrail = (canvas: HTMLCanvasElement | null) => {
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    const { width, height } = canvas;
    ctx.clearRect(0, 0, width, height);

    if (heartbeats.length < 2) return;

    // Find bounds
    let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
    heartbeats.forEach(h => {
      minX = Math.min(minX, h.pos_x); maxX = Math.max(maxX, h.pos_x);
      minZ = Math.min(minZ, h.pos_z); maxZ = Math.max(maxZ, h.pos_z);
    });

    const pad = 20;
    const rangeX = (maxX - minX) || 1;
    const rangeZ = (maxZ - minZ) || 1;
    const scale = Math.min((width - pad * 2) / rangeX, (height - pad * 2) / rangeZ);

    const toX = (x: number) => pad + (x - minX) * scale;
    const toZ = (z: number) => pad + (z - minZ) * scale;

    ctx.strokeStyle = '#7fd1ff';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(toX(heartbeats[0].pos_x), toZ(heartbeats[0].pos_z));
    heartbeats.forEach(h => ctx.lineTo(toX(h.pos_x), toZ(h.pos_z)));
    ctx.stroke();

    // Start/End points
    ctx.fillStyle = '#22c55e'; ctx.beginPath(); ctx.arc(toX(heartbeats[0].pos_x), toZ(heartbeats[0].pos_z), 4, 0, Math.PI*2); ctx.fill();
    ctx.fillStyle = '#ef4444'; ctx.beginPath(); ctx.arc(toX(heartbeats[heartbeats.length-1].pos_x), toZ(heartbeats[heartbeats.length-1].pos_z), 4, 0, Math.PI*2); ctx.fill();
  };

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
      <div className="bg-[#161a22] p-4 rounded-lg border border-[#232833]">
        <h3 className="text-[#7fd1ff] text-xs font-bold mb-4 uppercase">FPS vs Time (s)</h3>
        <div className="h-48 w-full">
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={chartData}>
              <CartesianGrid strokeDasharray="3 3" stroke="#232833" />
              <XAxis dataKey="time" stroke="#666" fontSize={10} />
              <YAxis stroke="#666" fontSize={10} domain={[0, 'auto']} />
              <Tooltip
                contentStyle={{ backgroundColor: '#161a22', border: '1px solid #232833' }}
                itemStyle={{ color: '#7fd1ff' }}
              />
              <Line type="monotone" dataKey="fps" stroke="#7fd1ff" dot={false} strokeWidth={2} />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </div>

      <div className="bg-[#161a22] p-4 rounded-lg border border-[#232833]">
        <h3 className="text-[#7fd1ff] text-xs font-bold mb-4 uppercase">Memory (MB)</h3>
        <div className="h-48 w-full">
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={chartData}>
              <CartesianGrid strokeDasharray="3 3" stroke="#232833" />
              <XAxis dataKey="time" stroke="#666" fontSize={10} />
              <YAxis stroke="#666" fontSize={10} domain={[0, 'auto']} />
              <Tooltip
                contentStyle={{ backgroundColor: '#161a22', border: '1px solid #232833' }}
                itemStyle={{ color: '#eab308' }}
              />
              <Area type="monotone" dataKey="mem" stroke="#eab308" fill="#eab308" fillOpacity={0.2} />
            </AreaChart>
          </ResponsiveContainer>
        </div>
      </div>

      <div className="bg-[#161a22] p-4 rounded-lg border border-[#232833] lg:col-span-2">
        <h3 className="text-[#7fd1ff] text-xs font-bold mb-4 uppercase">Movement Trail (Bird's Eye)</h3>
        <div className="flex justify-center bg-[#0c0e12] rounded border border-[#232833] p-2">
          <canvas
            ref={renderTrail}
            width={800}
            height={300}
            className="max-w-full h-auto"
          />
        </div>
      </div>
    </div>
  );
};
