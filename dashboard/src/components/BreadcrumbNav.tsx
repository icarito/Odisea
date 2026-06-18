import React from 'react';
import { ChevronRight, Home } from 'lucide-react';
import type { NavStackItem } from '../types';

interface BreadcrumbNavProps {
  stack: NavStackItem[];
  onNavigate: (index: number) => void;
  onHome: () => void;
}

export const BreadcrumbNav: React.FC<BreadcrumbNavProps> = ({ stack, onNavigate, onHome }) => {
  return (
    <nav className="flex items-center gap-2 px-4 py-2 text-[0.625rem] font-black uppercase tracking-widest text-text-muted bg-bg-primary border-b-2 border-black/10">
      <button 
        onClick={onHome}
        className="flex items-center gap-1 hover:text-accent transition-colors"
      >
        <Home size={12} />
        <span>Cockpit</span>
      </button>

      {stack.map((item, i) => (
        <React.Fragment key={i}>
          <ChevronRight size={10} className="opacity-40" />
          <button
            onClick={() => onNavigate(i)}
            className={`hover:text-accent transition-colors ${i === stack.length - 1 ? 'text-text-primary' : ''}`}
          >
            {item.label || item.view || item.tab}
          </button>
        </React.Fragment>
      ))}
    </nav>
  );
};
