import React, { useState } from 'react';
import { TagPicker } from './TagPicker';
import { TagBadge } from './TagBadge';
import { NotesField } from './NotesField';
import { RetroButton } from './retro';
import { Save } from 'lucide-react';

interface TaggableEntityEditorProps {
  entityId: string;
  type: 'player' | 'session' | 'hotzone' | 'scene';
  initialTags?: any[];
  initialNotes?: string;
  onSave: (data: { tags: any[], notes: string }) => void;
}

export const TaggableEntityEditor: React.FC<TaggableEntityEditorProps> = ({
  entityId,
  type,
  initialTags = [],
  initialNotes = '',
  onSave
}) => {
  const [tags, setTags] = useState(initialTags);
  const [notes, setNotes] = useState(initialNotes);

  const handleAddTag = (tag: any) => {
    if (!tags.find(t => t.label === tag.label)) {
      setTags([...tags, { ...tag, id: Math.random().toString() }]);
    }
  };

  return (
    <div className="flex flex-col gap-4 p-4 bg-bg-primary/50">
      <div className="space-y-1">
        <h3 className="text-[0.625rem] font-black uppercase tracking-[0.2em] text-accent">Edit {type} context</h3>
        <p className="text-[0.5rem] font-mono text-text-muted">{entityId}</p>
      </div>

      <div className="flex flex-wrap gap-2 py-2 border-y border-black/10 min-h-12 items-center">
        {tags.map(tag => (
          <TagBadge 
            key={tag.id} 
            tag={tag} 
            onRemove={() => setTags(tags.filter(t => t.id !== tag.id))} 
          />
        ))}
        {tags.length === 0 && <span className="text-[0.5rem] italic text-text-muted uppercase">No tags applied</span>}
      </div>

      <TagPicker onSelect={handleAddTag} />

      <NotesField value={notes} onChange={setNotes} />

      <RetroButton 
        variant="primary" 
        onClick={() => onSave({ tags, notes })}
        className="w-full gap-2 text-xs"
      >
        <Save size={14} /> SAVE METADATA
      </RetroButton>
    </div>
  );
};
