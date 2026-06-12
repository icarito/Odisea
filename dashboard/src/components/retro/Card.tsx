import 'react';

interface CardProps {
  children: React.ReactNode;
  className?: string;
  title?: React.ReactNode;
}

export const RetroCard: React.FC<CardProps> = ({ children, className = '', title }) => {
  return (
    <div className={`retro-card ${className}`}>
      {title && (
        <div className="border-b-4 border-black mb-4 pb-2">
          <h3 className="text-xs font-black uppercase tracking-widest text-accent flex items-center gap-2">
            <span className="shrink-0">▣</span> <span className="min-w-0 flex-1">{title}</span>
          </h3>
        </div>
      )}
      {children}
    </div>
  );
};
