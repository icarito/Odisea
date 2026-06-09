import React, { useState } from 'react';

interface LoginScreenProps {
  onLogin: (token: string) => void;
}

export const LoginScreen: React.FC<LoginScreenProps> = ({ onLogin }) => {
  const [token, setToken] = useState('');
  const [error, setError] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!token) {
      setError('Ingresá el token.');
      return;
    }
    onLogin(token);
  };

  return (
    <div className="fixed inset-0 flex items-center justify-center bg-bg-primary z-10">
      <div className="bg-bg-card border border-border-custom rounded-lg p-7 w-80">
        <h2 className="text-accent text-lg font-semibold mb-1">Odisea · Central</h2>
        <p className="text-text-muted text-xs mb-4">Observabilidad de telemetría en tiempo real. Ingresá el token de acceso.</p>
        <form onSubmit={handleSubmit}>
          <input
            type="password"
            value={token}
            onChange={(e) => setToken(e.target.value)}
            placeholder="ODISEA_BRIDGE_TOKEN"
            className="w-full p-2 bg-bg-primary border border-[#2a3140] rounded text-text-primary mb-3 focus:outline-none focus:border-accent"
            autoFocus
          />
          <button
            type="submit"
            className="w-full p-2 bg-[#1f6feb] hover:bg-[#388bfd] text-white rounded font-semibold transition-colors"
          >
            Conectar
          </button>
          {error && <div className="text-danger text-xs mt-2">{error}</div>}
        </form>
      </div>
    </div>
  );
};
