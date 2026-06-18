import React from 'react';
import { Tag as TagType } from '../types';

interface TagBadgeProps {
  tag: TagType;
  onRemove?: () => void;
}

export const TagBadge: React.FC<TagBadgeProps> = ({ tag, onRemove }) => {
  return (
    <div 
      className="inline-flex items-center gap-1.5 px-2 py-0.5 border border-black/20 bg-bg-primary shadow-[1px_1px_0px_0px_black]"
      style={{ borderLeftColor: tag.color, borderLeftWidth: tag.color ? '3px' : '1px' }}
    >
      <span className="text-[0.5rem] font-black uppercase tracking-tight">{tag.label}</span>
      {onRemove && (
        <button onClick={onRemove} className="hover:text-danger">×</button>
      )}
    </div>
  );
};
