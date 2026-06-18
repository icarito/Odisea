import React from 'react';

interface NotesFieldProps {
  value: string;
  onChange: (val: string) => void;
}

export const NotesField: React.FC<NotesFieldProps> = ({ value, onChange }) => {
  return (
    <div className="space-y-1.5">
      <label className="text-[0.5rem] font-bold uppercase tracking-widest text-text-muted">Free Notes</label>
      <textarea
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="w-full min-h-24 border-2 border-black bg-bg-card p-2 text-[0.625rem] font-mono focus:outline-none focus:ring-2 focus:ring-accent/50"
        placeholder="Add context, bug repro steps, or observations..."
      />
    </div>
  );
};
