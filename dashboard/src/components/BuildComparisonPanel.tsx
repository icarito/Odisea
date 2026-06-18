import React from 'react';

interface BuildComparisonPanelProps {
  buildA: any;
  buildB: any;
}

export const BuildComparisonPanel: React.FC<BuildComparisonPanelProps> = ({ buildA, buildB }) => {
  return (
    <div className="grid grid-cols-2 gap-4 h-full">
      <div className="border-2 border-black bg-bg-card p-4">
        <h3 className="text-xs font-black uppercase text-accent mb-4">Build A: {buildA.version}</h3>
        <div className="space-y-2 text-[0.625rem]">
           <div className="flex justify-between border-b border-black/10 pb-1">
              <span className="font-bold text-text-muted">AVG FPS</span>
              <span className="font-black text-success">58.2</span>
           </div>
           {/* ... more stats */}
        </div>
      </div>
      
      <div className="border-2 border-black bg-bg-card p-4">
        <h3 className="text-xs font-black uppercase text-accent mb-4">Build B: {buildB.version}</h3>
         <div className="space-y-2 text-[0.625rem]">
           <div className="flex justify-between border-b border-black/10 pb-1">
              <span className="font-bold text-text-muted">AVG FPS</span>
              <span className="font-black text-danger">42.1 (-27%)</span>
           </div>
           {/* ... more stats */}
        </div>
      </div>
    </div>
  );
};
