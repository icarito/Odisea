import 'react';

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'danger';
}

export const RetroButton: React.FC<ButtonProps> = ({ 
  children, 
  variant = 'primary', 
  className = '', 
  ...props 
}) => {
  const variantClass = `retro-btn-${variant}`;
  return (
    <button 
      className={`retro-btn ${variantClass} ${className}`}
      {...props}
    >
      {children}
    </button>
  );
};
