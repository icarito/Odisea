import React from 'react';
import { CollapsibleCard } from './retro';

interface CockpitPanelProps {
  title: string;
  children: React.ReactNode;
  colSpan?: number;
  rowSpan?: number;
  storageKey?: string;
  defaultOpen?: boolean;
  resizable?: boolean;
}

export const CockpitPanel: React.FC<CockpitPanelProps> = ({
  title,
  children,
  colSpan = 4,
  rowSpan = 1,
  storageKey,
  defaultOpen = true,
  resizable = false
}) => {
  const spanClass = `lg:col-span-${colSpan} lg:row-span-${rowSpan}`;
  
  return (
    <div className={spanClass}>
      <CollapsibleCard
        title={title}
        storageKey={storageKey}
        defaultOpen={defaultOpen}
        resizable={resizable}
        className="h-full"
      >
        <div className="h-full min-h-0 overflow-auto bg-bg-card/20 p-2">
          {children}
        </div>
      </CollapsibleCard>
    </div>
  );
};
