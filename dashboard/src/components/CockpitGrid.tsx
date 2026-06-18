import React from 'react';

interface CockpitGridProps {
  children: React.ReactNode;
}

export const CockpitGrid: React.FC<CockpitGridProps> = ({ children }) => {
  return (
    <div className="grid grid-cols-1 gap-4 p-4 lg:grid-cols-12 lg:grid-rows-[min-content_1fr]">
      {children}
    </div>
  );
};
