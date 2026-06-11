import 'react';

interface BadgeProps {
  children: React.ReactNode;
  color?: 'accent' | 'success' | 'warning' | 'danger';
  className?: string;
}

export const RetroBadge: React.FC<BadgeProps> = ({ 
  children, 
  color = 'accent', 
  className = '' 
}) => {
  const colorMap = {
    accent: 'bg-accent text-bg-primary',
    success: 'bg-success text-black',
    warning: 'bg-warning text-black',
    danger: 'bg-danger text-black',
  };

  return (
    <span className={`retro-badge ${colorMap[color]} ${className}`}>
      {children}
    </span>
  );
};
