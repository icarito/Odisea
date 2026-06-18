import React from 'react';
import { ReplayCandidateCard } from './ReplayCandidateCard';

interface HotzoneCandidatesListProps {
  candidates: any[];
  onSelect: (id: string) => void;
}

export const HotzoneCandidatesList: React.FC<HotzoneCandidatesListProps> = ({ candidates, onSelect }) => {
  return (
    <div className="flex flex-col gap-2">
      <h3 className="text-[0.5rem] font-bold uppercase tracking-widest text-text-muted mb-1 px-1">Select Replay Candidate</h3>
      {candidates.map((cand) => (
        <ReplayCandidateCard 
          key={cand.id} 
          candidate={cand} 
          onClick={() => onSelect(cand.id)} 
        />
      ))}
    </div>
  );
};
