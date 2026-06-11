import React from 'react';

interface Session {
  player_id: string;
  session_id: string;
  start_time: number;
  end_time: number;
  duration: number;
  scenes_visited: number;
  avg_fps: number;
  low_fps_pct: number;
  avg_mem: number;
}

interface HistoricalTableProps {
  sessions: Session[];
  onSelectSession: (session: Session) => void;
}

export const HistoricalTable: React.FC<HistoricalTableProps> = ({ sessions, onSelectSession }) => {
  return (
    <div className="w-full overflow-x-auto bg-[#0c0e12] rounded-lg border border-[#232833]">
      <table className="w-full text-left text-xs">
        <thead className="bg-[#161a22] text-[#7fd1ff] uppercase font-bold border-b border-[#232833]">
          <tr>
            <th className="px-4 py-3">Player ID</th>
            <th className="px-4 py-3">Start Date</th>
            <th className="px-4 py-3">Duration</th>
            <th className="px-4 py-3">Scenes</th>
            <th className="px-4 py-3">Avg FPS</th>
            <th className="px-4 py-3">% Low FPS</th>
            <th className="px-4 py-3">Avg Mem</th>
            <th className="px-4 py-3">Action</th>
          </tr>
        </thead>
        <tbody className="text-white divide-y divide-[#232833]">
          {sessions.map((s) => (
            <tr key={s.session_id} className="hover:bg-[#1c212b] transition-colors">
              <td className="px-4 py-3 font-mono">{s.player_id.substring(0, 12)}...</td>
              <td className="px-4 py-3">{new Date(s.start_time * 1000).toLocaleString()}</td>
              <td className="px-4 py-3">{Math.floor(s.duration / 60)}m {Math.floor(s.duration % 60)}s</td>
              <td className="px-4 py-3">{s.scenes_visited}</td>
              <td className={`px-4 py-3 font-bold ${s.avg_fps < 30 ? "text-red-400" : "text-green-400"}`}>
                {s.avg_fps.toFixed(1)}
              </td>
              <td className={`px-4 py-3 ${s.low_fps_pct > 30 ? "text-red-400" : ""}`}>
                {s.low_fps_pct.toFixed(1)}%
              </td>
              <td className="px-4 py-3">{s.avg_mem.toFixed(0)} MB</td>
              <td className="px-4 py-3">
                <button
                  onClick={() => onSelectSession(s)}
                  className="bg-[#7fd1ff] hover:bg-[#7fd1ff]/80 text-black px-3 py-1 rounded font-bold transition-colors"
                >
                  VIEW
                </button>
              </td>
            </tr>
          ))}
          {sessions.length === 0 && (
            <tr>
              <td colSpan={8} className="px-4 py-10 text-center text-gray-500 italic">
                No historical sessions found. Run the import script or wait for more heartbeats.
              </td>
            </tr>
          )}
        </tbody>
      </table>
    </div>
  );
};
