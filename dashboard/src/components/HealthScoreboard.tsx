import React from 'react';

interface HealthScoreboardProps {
  stats: {
    sessions: number;
    players: number;
    playTime: string;
    avgFps: number;
  };
}

export const HealthScoreboard: React.FC<HealthScoreboardProps> = ({ stats }) => {
  const fpsColor = stats.avgFps > 45 ? 'text-success' : stats.avgFps > 30 ? 'text-warning' : 'text-danger';

  return (
    <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
      <div className="border-2 border-black bg-bg-card p-2 shadow-[2px_2px_0px_0px_black]">
        <div className="text-[0.5rem] font-bold uppercase text-text-muted">Sessions</div>
        <div className="text-xl font-black">{stats.sessions}</div>
      </div>
      <div className="border-2 border-black bg-bg-card p-2 shadow-[2px_2px_0px_0px_black]">
        <div className="text-[0.5rem] font-bold uppercase text-text-muted">Active Players</div>
        <div className="text-xl font-black text-accent">{stats.players}</div>
      </div>
      <div className="border-2 border-black bg-bg-card p-2 shadow-[2px_2px_0px_0px_black]">
        <div className="text-[0.5rem] font-bold uppercase text-text-muted">Play Time</div>
        <div className="text-xl font-black truncate">{stats.playTime}</div>
      </div>
      <div className="border-2 border-black bg-bg-card p-2 shadow-[2px_2px_0px_0px_black]">
        <div className="text-[0.5rem] font-bold uppercase text-text-muted">Avg FPS</div>
        <div className={`text-xl font-black ${fpsColor}`}>{stats.avgFps.toFixed(1)}</div>
      </div>
    </div>
  );
};
