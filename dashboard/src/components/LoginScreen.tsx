import React from 'react';
import { RetroButton, RetroInput } from './retro';

export function LoginScreen({ onLogin }: { onLogin: (token: string) => void }) {
  const [password, setPassword] = React.useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onLogin(password);
  };

  return (
    <div className="min-h-screen bg-bg-primary flex items-center justify-center p-6 font-mono crt-effect">
      <div className="w-full max-w-sm">
        <div className="bg-bg-card border-4 border-black shadow-[8px_8px_0px_0px_black] p-8 relative overflow-hidden">
          <div className="absolute top-0 left-0 w-full h-1 bg-accent/30" />
          
          <div className="mb-8 text-center">
            <h1 className="text-2xl font-black text-accent italic tracking-tighter mb-2">ODISEA CENTRAL</h1>
            <div className="text-[0.625rem] text-text-muted uppercase tracking-[0.3em]">Access Point v2.0.4</div>
          </div>

          <form onSubmit={handleSubmit} className="flex flex-col gap-6">
            <RetroInput
              label="Security Token"
              type="password"
              placeholder="••••••••"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              sublabel="Encrypted link required"
            />
            
            <RetroButton type="submit" className="py-4 text-sm tracking-widest">
              INITIALIZE_SYSTEM
            </RetroButton>
          </form>

          <div className="mt-8 pt-6 border-t-2 border-black/20 flex justify-between items-center text-[0.5rem] text-text-muted uppercase font-bold">
            <span>Status: Ready</span>
            <span>Loc: Remote</span>
          </div>
        </div>
        
        <div className="mt-4 text-center text-[0.5rem] text-text-muted/40 uppercase tracking-widest">
          Unauthorized access is logged and reported
        </div>
      </div>
    </div>
  );
}
