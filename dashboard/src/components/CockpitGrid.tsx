import React from 'react';
import { Panel, PanelGroup, PanelResizeHandle } from 'react-resizable-panels';

interface CockpitGridProps {
  // Expected order: [ActivePlayers, MainView (Map), Scoreboard, EventTimeline]
  children: React.ReactNode[];
  storageKey?: string;
}

export const CockpitGrid: React.FC<CockpitGridProps> = ({ children, storageKey }) => {
  // Mobile layout (single column scroll)
  const mobileLayout = (
    <div className="flex flex-col gap-4 p-4 lg:hidden">
      {children.map((child, i) => (
        <div key={i}>{child}</div>
      ))}
    </div>
  );

  // Desktop layout (2 columns with resizable split)
  const desktopLayout = (
    <div className="hidden h-full w-full lg:block">
      <PanelGroup direction="horizontal" autoSaveId={storageKey ? `${storageKey}_horizontal` : undefined}>
        {/* Left Column */}
        <Panel defaultSize={35} minSize={20}>
          <div className="flex h-full flex-col gap-4 overflow-y-auto p-4">
            <div className="flex-none">{children[0]}</div>
            <div className="flex-1 min-h-0">{children[2]}</div>
          </div>
        </Panel>

        <PanelResizeHandle className="group relative w-2 bg-bg-primary transition-colors hover:bg-accent/20">
          <div className="absolute inset-y-0 left-1/2 w-[2px] -translate-x-1/2 bg-black/40 group-hover:bg-accent" />
        </PanelResizeHandle>

        {/* Right Column */}
        <Panel defaultSize={65}>
          <PanelGroup direction="vertical" autoSaveId={storageKey ? `${storageKey}_vertical` : undefined}>
            <Panel defaultSize={60} minSize={30}>
              <div className="h-full p-4 pl-0">
                {children[1]}
              </div>
            </Panel>
            
            <PanelResizeHandle className="group relative h-2 bg-bg-primary transition-colors hover:bg-accent/20">
              <div className="absolute inset-x-0 top-1/2 h-[2px] -translate-y-1/2 bg-black/40 group-hover:bg-accent" />
            </PanelResizeHandle>

            <Panel defaultSize={40}>
              <div className="h-full overflow-y-auto p-4 pl-0 pt-0">
                {children[3]}
              </div>
            </Panel>
          </PanelGroup>
        </Panel>
      </PanelGroup>
    </div>
  );

  return (
    <div className="h-full w-full overflow-hidden">
      {mobileLayout}
      {desktopLayout}
    </div>
  );
};
