import React from 'react';
import { TrendingDown } from 'lucide-react';

interface RegressionDetectorBarProps {
  regressions: any[];
}

export const RegressionDetectorBar: React.FC<RegressionDetectorBarProps> = ({ regressions }) => {
  if (regressions.length === 0) return null;

  return (
    <div className="flex items-center gap-4 bg-danger/20 border-2 border-danger p-2 mb-4">
      <div className="flex items-center gap-2 text-danger">
        <TrendingDown size={16} />
        <span className="text-[0.625rem] font-black uppercase">Possible Regressions Detected</span>
      </div>
      
      <div className="flex gap-2">
        {regressions.map((r, i) => (
          <div key={i} className="bg-danger text-white text-[0.5rem] font-black px-1.5 py-0.5 uppercase">
            {r.scene}: -{r.percentage}%
          </div>
        ))}
      </div>
    </div>
  );
};
