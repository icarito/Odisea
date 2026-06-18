import React from 'react';
import { ChevronRight, PlayCircle } from 'lucide-react';

interface ReplayBreadcrumbProps {
  scene: string;
  hotzoneId?: string;
  onBack: () => void;
}

export const ReplayBreadcrumb: React.FC<ReplayBreadcrumbProps> = ({ scene, hotzoneId, onBack }) => {
  return (
    <div className="flex items-center gap-2 px-4 py-1 text-[0.625rem] font-bold uppercase tracking-wider text-text-muted">
      <button onClick={onBack} className="hover:text-accent">Replays</button>
      <ChevronRight size={10} className="opacity-30" />
      <span className="text-text-primary flex items-center gap-1.5">
        <PlayCircle size={10} />
        {scene} {hotzoneId ? `· HZ ${hotzoneId.slice(0, 6)}` : '· Manual Session'}
      </span>
    </div>
  );
};
