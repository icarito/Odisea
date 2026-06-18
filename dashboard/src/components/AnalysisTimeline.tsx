import React from 'react';
import { 
  LineChart, 
  Line, 
  XAxis, 
  YAxis, 
  CartesianGrid, 
  Tooltip, 
  ResponsiveContainer
} from 'recharts';
import { BuildMarkersLayer } from './BuildMarkersLayer';

interface AnalysisTimelineProps {
  data: any[];
  builds: any[];
}

export const AnalysisTimeline: React.FC<AnalysisTimelineProps> = ({ data, builds }) => {
  return (
    <div className="h-full w-full bg-bg-card p-4 border-2 border-black shadow-retro relative overflow-hidden">
      <div className="absolute top-4 left-4 z-10">
        <h3 className="text-[0.625rem] font-black uppercase tracking-widest text-accent">Performance Analysis</h3>
      </div>
      
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={data} margin={{ top: 40, right: 20, left: 0, bottom: 20 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#232833" />
          <XAxis 
            dataKey="timestamp" 
            stroke="#666" 
            fontSize={10} 
            tickFormatter={(v) => new Date(v * 1000).toLocaleDateString()} 
          />
          <YAxis stroke="#666" fontSize={10} domain={[0, 70]} />
          <Tooltip 
            contentStyle={{ backgroundColor: '#13161c', border: '2px solid #000', fontSize: '10px' }}
          />
          
          <BuildMarkersLayer builds={builds} />
          
          <Line 
            type="monotone" 
            dataKey="fps" 
            stroke="#7fd1ff" 
            strokeWidth={2} 
            dot={{ r: 2 }} 
            isAnimationActive={false} 
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
};
