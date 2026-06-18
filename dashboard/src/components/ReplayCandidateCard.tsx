import React from 'react';
import { User, Activity } from 'lucide-react';

interface ReplayCandidateCardProps {
  candidate: any;
  onClick: () => void;
}

export const ReplayCandidateCard: React.FC<ReplayCandidateCardProps> = ({ candidate, onClick }) => {
  return (
    <button
      onClick={onClick}
      className="flex items-center gap-3 w-full border-2 border-black bg-bg-card p-2 text-left shadow-[2px_2px_0px_0px_black] hover:bg-accent/5 transition-colors"
    >
      <div className="h-10 w-10 shrink-0 border-2 border-black bg-bg-primary flex items-center justify-center text-text-muted">
        <User size={20} />
      </div>
      
      <div className="flex-1 min-w-0">
        <div className="flex justify-between items-baseline">
          <span className="text-[0.625rem] font-black uppercase truncate">{candidate.player_id.slice(0, 12)}</span>
          <span className="text-[0.5rem] font-bold text-text-muted">{candidate.platform}</span>
        </div>
        <div className="flex items-center gap-2 mt-1">
          <Activity size={10} className="text-text-muted" />
          <span className="text-[0.5625rem] font-black text-danger">Dropped to 15 FPS</span>
        </div>
      </div>
    </button>
  );
};
