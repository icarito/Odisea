import React from 'react';

interface TagCategoryGroupProps {
  category: string;
  tags: any[];
  onSelect: (tag: any) => void;
}

export const TagCategoryGroup: React.FC<TagCategoryGroupProps> = ({ category, tags, onSelect }) => {
  return (
    <div className="space-y-1.5">
      <div className="text-[0.5rem] font-bold uppercase text-text-muted/60">{category}</div>
      <div className="flex flex-wrap gap-1">
        {tags.map((tag, i) => (
          <button
            key={i}
            onClick={() => onSelect(tag)}
            className="border border-black/20 bg-bg-primary px-1.5 py-0.5 text-[0.5rem] font-black uppercase hover:bg-accent hover:text-black transition-colors"
          >
            {tag.label}
          </button>
        ))}
      </div>
    </div>
  );
};
