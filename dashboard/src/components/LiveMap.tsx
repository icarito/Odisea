import React, { useEffect, useRef, useState } from 'react';

interface ActiveGhost {
  player_id: string;
  session_id: string;
  scene: string;
  pos_x: number;
  pos_y: number;
  pos_z: number;
  fps: number;
  last_seen: number;
}

interface LiveMapProps {
  ghosts: ActiveGhost[];
  sceneName: string;
}

export const LiveMap: React.FC<LiveMapProps> = ({ ghosts, sceneName }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [hoveredGhost, setHoveredGhost] = useState<ActiveGhost | null>(null);
  const [mousePos, setMousePos] = useState({ x: 0, y: 0 });

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const render = () => {
      const { width, height } = canvas;
      ctx.clearRect(0, 0, width, height);

      // Draw Grid Background
      ctx.strokeStyle = '#232833';
      ctx.lineWidth = 1;
      const gridSize = 40;
      for (let x = 0; x < width; x += gridSize) {
        ctx.beginPath();
        ctx.moveTo(x, 0);
        ctx.lineTo(x, height);
        ctx.stroke();
      }
      for (let y = 0; y < height; y += gridSize) {
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(width, y);
        ctx.stroke();
      }

      // Draw Scene Center
      ctx.strokeStyle = '#2a3140';
      ctx.setLineDash([5, 5]);
      ctx.beginPath();
      ctx.moveTo(width / 2, 0); ctx.lineTo(width / 2, height);
      ctx.moveTo(0, height / 2); ctx.lineTo(width, height / 2);
      ctx.stroke();
      ctx.setLineDash([]);

      // Draw Ghosts
      const scale = 2; // 1 unit = 2 pixels
      ghosts.forEach(ghost => {
        if (ghost.scene !== sceneName && sceneName !== "") return;

        const screenX = width / 2 + ghost.pos_x * scale;
        const screenZ = height / 2 + ghost.pos_z * scale;

        let color = '#22c55e'; // Green > 45
        if (ghost.fps < 30) color = '#ef4444'; // Red < 30
        else if (ghost.fps < 45) color = '#eab308'; // Yellow 30-45

        ctx.fillStyle = color;
        ctx.beginPath();
        ctx.arc(screenX, screenZ, 6, 0, Math.PI * 2);
        ctx.fill();

        // Glow effect
        ctx.shadowBlur = 10;
        ctx.shadowColor = color;
        ctx.stroke();
        ctx.shadowBlur = 0;

        // Label
        ctx.fillStyle = 'white';
        ctx.font = '10px Inter, sans-serif';
        ctx.fillText(ghost.player_id.substring(0, 8), screenX + 8, screenZ + 4);
      });
    };

    render();
  }, [ghosts, sceneName]);

  const handleMouseMove = (e: React.MouseEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    setMousePos({ x: e.clientX, y: e.clientY });

    const scale = 2;
    const found = ghosts.find(g => {
      if (g.scene !== sceneName && sceneName !== "") return false;
      const gx = canvas.width / 2 + g.pos_x * scale;
      const gz = canvas.height / 2 + g.pos_z * scale;
      return Math.sqrt((x - gx) ** 2 + (y - gz) ** 2) < 10;
    });
    setHoveredGhost(found || null);
  };

  return (
    <div className="w-full h-full relative bg-[#0c0e12] rounded-lg overflow-hidden border border-[#232833]">
      <canvas
        ref={canvasRef}
        width={800}
        height={600}
        onMouseMove={handleMouseMove}
        onMouseLeave={() => setHoveredGhost(null)}
        className="w-full h-full cursor-crosshair"
      />

      <div className="absolute top-4 left-4 flex flex-col gap-2 pointer-events-none">
        <div className="bg-[#161a22]/90 px-3 py-1.5 rounded text-[10px] border border-[#232833] text-white">
          LIVE GHOSTS: <span className="text-[#7fd1ff] font-bold">{ghosts.filter(g => g.scene === sceneName || sceneName === "").length}</span>
        </div>
      </div>

      {hoveredGhost && (
        <div
          className="fixed bg-[#161a22]/95 border border-[#232833] p-3 rounded shadow-2xl z-50 pointer-events-none text-white text-xs"
          style={{ left: mousePos.x + 15, top: mousePos.y + 15 }}
        >
          <div className="font-bold text-[#7fd1ff] border-b border-[#232833] pb-1 mb-2">
            {hoveredGhost.player_id}
          </div>
          <div className="grid grid-cols-2 gap-x-4 gap-y-1">
            <span className="text-gray-400">FPS:</span>
            <span className={hoveredGhost.fps < 30 ? "text-red-400 font-bold" : "text-white"}>
              {hoveredGhost.fps.toFixed(1)}
            </span>
            <span className="text-gray-400">Scene:</span>
            <span>{hoveredGhost.scene}</span>
            <span className="text-gray-400">Position:</span>
            <span>{hoveredGhost.pos_x.toFixed(1)}, {hoveredGhost.pos_z.toFixed(1)}</span>
            <span className="text-gray-400">Last Seen:</span>
            <span>{new Date(hoveredGhost.last_seen * 1000).toLocaleTimeString()}</span>
          </div>
        </div>
      )}
    </div>
  );
};
