import React from 'react';
import { CollapsibleCard } from './retro/CollapsibleCard';

interface CockpitPanelProps {
  children: React.ReactNode;
  title: string;
  storageKey: string;
  defaultOpen?: boolean;
  count?: number;
  className?: string;
  resizable?: boolean;
  initialHeight?: number;
}

export const CockpitPanel: React.FC<CockpitPanelProps> = ({
  children,
  title,
  storageKey,
  defaultOpen = true,
  count,
  className = '',
  resizable = false,
  initialHeight,
}) => {
  return (
    <CollapsibleCard
      title={title}
      storageKey={storageKey}
      defaultOpen={defaultOpen}
      count={count}
      className={`h-full ${className}`}
      resizable={resizable}
      initialHeight={initialHeight}
    >
      <div className="p-4 h-full overflow-auto">
        {children}
      </div>
    </CollapsibleCard>
  );
};
