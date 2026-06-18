import React, { useState, useEffect, useRef } from 'react';
import { ChevronDown, ChevronRight, GripHorizontal } from 'lucide-react';

interface CollapsibleCardProps {
  children: React.ReactNode;
  title: string;
  count?: number;
  storageKey?: string;
  defaultOpen?: boolean;
  className?: string;
  resizable?: boolean;
  initialHeight?: number;
}

export const CollapsibleCard: React.FC<CollapsibleCardProps> = ({
  children,
  title,
  count,
  storageKey = '',
  defaultOpen = true,
  className = '',
  resizable = false,
  initialHeight = 300,
}) => {
  const [isOpen, setIsOpen] = useState(() => {
    const saved = localStorage.getItem(storageKey);
    return saved !== null ? saved === 'true' : defaultOpen;
  });

  const [height, setHeight] = useState(() => {
    if (!resizable) return undefined;
    const saved = localStorage.getItem(`${storageKey}_height`);
    return saved !== null ? parseInt(saved, 10) : initialHeight;
  });

  const isResizing = useRef(false);

  useEffect(() => {
    localStorage.setItem(storageKey, String(isOpen));
  }, [isOpen, storageKey]);

  useEffect(() => {
    if (resizable && height !== undefined) {
      localStorage.setItem(`${storageKey}_height`, String(height));
    }
  }, [height, resizable, storageKey]);

  const toggle = () => setIsOpen(!isOpen);

  const startResizing = (e: React.MouseEvent | React.TouchEvent) => {
    e.preventDefault();
    isResizing.current = true;
    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', stopResizing);
    document.addEventListener('touchmove', handleTouchMove);
    document.addEventListener('touchend', stopResizing);
  };

  const stopResizing = () => {
    isResizing.current = false;
    document.removeEventListener('mousemove', handleMouseMove);
    document.removeEventListener('mouseup', stopResizing);
    document.removeEventListener('touchmove', handleTouchMove);
    document.removeEventListener('touchend', stopResizing);
  };

  const handleMouseMove = (e: MouseEvent) => {
    if (!isResizing.current) return;
    const newHeight = Math.max(100, e.clientY - (containerRef.current?.getBoundingClientRect().top || 0));
    setHeight(newHeight);
  };

  const handleTouchMove = (e: TouchEvent) => {
    if (!isResizing.current) return;
    const touch = e.touches[0];
    const newHeight = Math.max(100, touch.clientY - (containerRef.current?.getBoundingClientRect().top || 0));
    setHeight(newHeight);
  };

  const containerRef = useRef<HTMLDivElement>(null);

  return (
    <div
      ref={containerRef}
      className={`border-2 border-black bg-bg-card shadow-[2px_2px_0px_0px_black] overflow-hidden flex flex-col ${className}`}
      style={isOpen && resizable ? { height: `${height}px` } : {}}
    >
      <button
        type="button"
        onClick={toggle}
        className="flex items-center justify-between gap-2 border-b-2 border-black bg-bg-primary px-3 py-2 text-left hover:bg-accent/5 transition-colors"
      >
        <div className="flex items-center gap-2 overflow-hidden">
          {isOpen ? <ChevronDown size={14} className="shrink-0" /> : <ChevronRight size={14} className="shrink-0" />}
          <span className="truncate text-[0.625rem] font-black uppercase tracking-widest text-text-muted">
            {title} {count !== undefined && `(${count})`}
          </span>
        </div>
      </button>

      {isOpen && (
        <div className="relative flex-1 min-h-0 overflow-auto">
          {children}
          {resizable && (
            <div
              onMouseDown={startResizing}
              onTouchStart={startResizing}
              className="absolute bottom-0 left-0 right-0 h-4 cursor-ns-resize flex items-center justify-center group bg-gradient-to-t from-black/5 to-transparent"
            >
              <GripHorizontal size={14} className="text-text-muted opacity-30 group-hover:opacity-100 transition-opacity" />
            </div>
          )}
        </div>
      )}
    </div>
  );
};
