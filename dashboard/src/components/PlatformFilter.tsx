import type React from 'react';
import { ChevronDown, Monitor, Server, Smartphone } from 'lucide-react';

export const PLATFORM_META: Record<string, { label: string; color: string; icon: React.ReactNode }> = {
  server: { label: 'Server', color: 'bg-red-500', icon: <Server size={12} /> },
  android: { label: 'Android', color: 'bg-green-500', icon: <Smartphone size={12} /> },
  ios: { label: 'iOS', color: 'bg-purple-500', icon: <Smartphone size={12} /> },
  linux: { label: 'Linux', color: 'bg-yellow-500', icon: <Monitor size={12} /> },
  windows: { label: 'Windows', color: 'bg-blue-500', icon: <Monitor size={12} /> },
  macos: { label: 'macOS', color: 'bg-zinc-300', icon: <Monitor size={12} /> },
  web: { label: 'Web', color: 'bg-cyan-500', icon: <Monitor size={12} /> },
};

const KNOWN_ORDER = ['server', 'android', 'ios', 'linux', 'windows', 'macos', 'web'];

interface PlatformFilterProps {
  platforms: string[];
  selected: Set<string>;
  onToggle: (platform: string) => void;
}

export const PlatformFilter: React.FC<PlatformFilterProps> = ({ platforms, selected, onToggle }) => {
  const visible = KNOWN_ORDER.filter((p) => platforms.includes(p));

  if (visible.length === 0) return null;

  const activeCount = visible.filter((platform) => selected.has(platform)).length;

  return (
    <details className="relative shrink-0">
      <summary className="flex cursor-pointer list-none items-center gap-1 border-2 border-black bg-bg-primary px-2 py-1 text-[0.625rem] font-black uppercase marker:hidden hover:bg-accent hover:text-black">
        Platform
        <span className="text-text-muted">{activeCount}/{visible.length}</span>
        <ChevronDown size={12} />
      </summary>
      <div className="absolute right-0 top-full z-50 mt-1 w-44 border-2 border-black bg-bg-card p-2 shadow-[3px_3px_0px_0px_black]">
        {visible.map((platform) => {
          const meta = PLATFORM_META[platform];
          const checked = selected.has(platform);
          return (
            <label
              key={platform}
              className={`flex cursor-pointer items-center gap-2 px-2 py-1.5 text-[0.625rem] font-black uppercase transition-colors hover:bg-accent/10 ${checked ? 'text-text-primary' : 'text-text-muted'}`}
              title={`Toggle ${meta.label}`}
            >
              <input
                type="checkbox"
                checked={checked}
                onChange={() => onToggle(platform)}
                className="h-3 w-3 accent-current"
              />
              <span className={`h-2.5 w-2.5 border border-black ${meta.color}`} />
              {meta.icon}
              <span>{meta.label}</span>
            </label>
          );
        })}
      </div>
    </details>
  );
};
