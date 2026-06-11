import { RetroButton } from './retro';

export const HistoricalTable = ({ sessions, onSelectSession }: { sessions: any[], onSelectSession: (s: any) => void }) => {
  return (
    <div className="w-full overflow-x-auto border-4 border-black">
      <table className="w-full text-left font-mono text-[0.625rem]">
        <thead className="bg-black text-accent uppercase font-black">
          <tr>
            <th className="p-3">Player ID</th>
            <th className="p-3">Session</th>
            <th className="p-3">Scene</th>
            <th className="p-3">Duration</th>
            <th className="p-3 text-right">Action</th>
          </tr>
        </thead>
        <tbody className="divide-y-2 divide-black/20">
          {sessions.map((s, idx) => (
            <tr key={idx} className="hover:bg-accent/5">
              <td className="p-3 truncate max-w-[120px]">{s.player_id}</td>
              <td className="p-3 font-mono opacity-60">{s.session_id.substring(0, 8)}</td>
              <td className="p-3 text-accent">{s.scene}</td>
              <td className="p-3">{(s.duration / 60).toFixed(1)}m</td>
              <td className="p-3 text-right">
                <RetroButton 
                    variant="secondary" 
                    onClick={() => onSelectSession(s)}
                    className="py-1 px-2 text-[0.5rem]"
                >
                    LOAD_DATA
                </RetroButton>
              </td>
            </tr>
          ))}
          {sessions.length === 0 && (
            <tr>
              <td colSpan={5} className="p-10 text-center text-text-muted italic bg-bg-primary/50">
                DATABASE EMPTY // NO HISTORICAL RECORDS
              </td>
            </tr>
          )}
        </tbody>
      </table>
    </div>
  );
};
