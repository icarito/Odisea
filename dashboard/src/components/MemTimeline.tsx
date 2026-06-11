import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';

export const MemTimeline = ({ data }: { data: any[] }) => {
  return (
    <div className="flex-1 w-full min-h-[120px]">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={data}>
          <CartesianGrid strokeDasharray="3 3" stroke="#232833" vertical={false} />
          <XAxis hide dataKey="timestamp" />
          <YAxis 
            tick={{ fontSize: 9, fill: '#6b7280' }} 
            axisLine={false}
            tickLine={false}
          />
          <Tooltip
            contentStyle={{ 
                backgroundColor: '#13161c', 
                border: '4px solid #000', 
                fontSize: '10px',
                fontFamily: 'monospace',
                borderRadius: '0px',
                boxShadow: '4px 4px 0px 0px #000'
            }}
            itemStyle={{ color: '#3fb950' }}
          />
          <Area 
            type="monotone" 
            dataKey="value" 
            stroke="#3fb950" 
            strokeWidth={2}
            fill="#3fb950" 
            fillOpacity={0.1} 
            isAnimationActive={false}
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
};
