import 'react';

interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  sublabel?: string;
}

export const RetroInput: React.FC<InputProps> = ({ label, sublabel, className = '', ...props }) => {
  return (
    <div className="w-full font-mono">
      {label && (
        <label className="block text-[0.625rem] font-bold uppercase tracking-[0.25em] mb-2 text-text-muted">
          ✎ {label}
        </label>
      )}
      <div className="relative">
        <input
          className={`retro-input ${className}`}
          {...props}
        />
        <span className="absolute -bottom-1 left-2 right-2 border-t-2 border-dashed border-black/40" />
      </div>
      {sublabel && (
        <p className="mt-1.5 text-[0.625rem] opacity-50 uppercase tracking-widest">
          {sublabel}
        </p>
      )}
    </div>
  );
};

interface SelectProps extends React.SelectHTMLAttributes<HTMLSelectElement> {
    label?: string;
}

export const RetroSelect: React.FC<SelectProps> = ({ label, children, className = '', ...props }) => {
    return (
        <div className="w-full font-mono">
          {label && (
            <label className="block text-[0.625rem] font-bold uppercase tracking-[0.25em] mb-2 text-text-muted">
              ✎ {label}
            </label>
          )}
          <select
            className={`retro-input appearance-none bg-bg-primary ${className}`}
            {...props}
          >
            {children}
          </select>
        </div>
      );
}
