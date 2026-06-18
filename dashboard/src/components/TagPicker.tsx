import React from 'react';
import { TagCategoryGroup } from './TagCategoryGroup';

interface TagPickerProps {
  onSelect: (tag: any) => void;
}

export const TagPicker: React.FC<TagPickerProps> = ({ onSelect }) => {
  const categories = [
    { name: 'Persona', tags: [{ label: 'QA', color: '#7fd1ff' }, { label: 'Dev', color: '#3fb950' }] },
    { name: 'Platform', tags: [{ label: 'Low-end', color: '#f85149' }, { label: 'Web', color: '#d29922' }] }
  ];

  return (
    <div className="border-2 border-black bg-bg-card p-3 shadow-retro space-y-3">
      <h4 className="text-[0.5rem] font-bold uppercase tracking-widest text-text-muted">Quick Tags</h4>
      {categories.map(cat => (
        <TagCategoryGroup 
          key={cat.name} 
          category={cat.name} 
          tags={cat.tags} 
          onSelect={onSelect} 
        />
      ))}
    </div>
  );
};
