import React from 'react';
import { ChevronRight, Home } from 'lucide-react';

interface BreadcrumbNavProps {
  stack: { label: string; id: string }[];
  onNavigate: (id: string) => void;
}

export const BreadcrumbNav: React.FC<BreadcrumbNavProps> = ({ stack, onNavigate }) => {
  return (
    <div className="flex items-center gap-1.5 px-4 py-1 text-[0.625rem] font-bold uppercase tracking-wider text-text-muted">
      <button 
        onClick={() => onNavigate('dashboard')}
        className="flex items-center gap-1 hover:text-accent"
      >
        <Home size={10} />
      </button>
      
      {stack.map((item, idx) => (
        <React.Fragment key={item.id}>
          <ChevronRight size={10} className="opacity-30" />
          <button
            onClick={() => onNavigate(item.id)}
            className={`hover:text-accent ${idx === stack.length - 1 ? 'text-text-primary' : ''}`}
          >
            {item.label}
          </button>
        </React.Fragment>
      ))}
    </div>
  );
};
