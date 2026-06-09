import React from 'react';

interface TimelineEvent {
  scene: string;
  timestamp: number;
}

interface SessionTimelineProps {
  events: TimelineEvent[];
}

const SCENE_COLORS: Record<string, string> = {
  'Dome_Crio': '#3fb950', // Success/Green
  'Exterior': '#d29922',  // Warning/Yellow
  'ZeroG': '#7fd1ff',     // Accent/Cyan
  'Unknown': '#6b7280'    // Muted/Gray
};

export const SessionTimeline: React.FC<SessionTimelineProps> = ({ events }) => {
  if (events.length === 0) return null;

  const startTime = events[0].timestamp;

  // Group events into segments
  const segments: { scene: string, start: number, end: number }[] = [];
  for (let i = 0; i < events.length; i++) {
    const current = events[i];
    const next = events[i+1];

    if (segments.length > 0 && segments[segments.length-1].scene === current.scene) {
      segments[segments.length-1].end = next ? next.timestamp : current.timestamp;
    } else {
      segments.push({
        scene: current.scene,
        start: current.timestamp,
        end: next ? next.timestamp : current.timestamp
      });
    }
  }

  // Ensure last segment has some width if it's the only one or very short
  if (segments.length > 0) {
    const last = segments[segments.length - 1];
    if (last.end === last.start) {
        last.end = last.start + 1;
    }
  }

  const finalEndTime = segments[segments.length - 1].end;
  const finalDuration = finalEndTime - startTime;

  return (
    <div className="w-full h-4 bg-bg-primary rounded-full overflow-hidden flex border border-border-custom relative group">
      {segments.map((s, i) => {
        const width = ((s.end - s.start) / finalDuration) * 100;
        const color = SCENE_COLORS[s.scene] || SCENE_COLORS['Unknown'];
        return (
          <div
            key={i}
            style={{ width: `${width}%`, backgroundColor: color }}
            className="h-full border-r border-black/20"
            title={`${s.scene} (${Math.round(s.end - s.start)}s)`}
          />
        );
      })}
      {/* Tooltip or Legend could go here */}
    </div>
  );
};
