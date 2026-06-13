import React, { useState, useEffect } from 'react';
import { RetroCard, RetroButton } from './retro';
import { usePushNotifications } from '../hooks/usePushNotifications';
import { Bell, BellOff, Settings2 } from 'lucide-react';

export const NotificationSettings: React.FC = () => {
  const { subscription, isSupported, isSubscribing, subscribe, unsubscribe } = usePushNotifications();
  const [enabledEvents, setEnabledEvents] = useState({
    disconnect: true,
    bridge: true,
    alert: true
  });

  useEffect(() => {
    const saved = localStorage.getItem('odisea_push_settings');
    if (saved) {
      setEnabledEvents(JSON.parse(saved));
    }
  }, []);

  const toggleEvent = async (event: keyof typeof enabledEvents) => {
    const next = { ...enabledEvents, [event]: !enabledEvents[event] };
    setEnabledEvents(next);
    localStorage.setItem('odisea_push_settings', JSON.stringify(next));
    
    // Sync with backend if subscribed
    if (subscription) {
      const { subscribePush } = await import('../api');
      await subscribePush(subscription, next);
    }
  };

  if (!isSupported) {
    return (
      <RetroCard title="Notificaciones" className="opacity-50">
        <p className="text-[0.625rem] text-text-muted">Push no soportado en este navegador.</p>
      </RetroCard>
    );
  }

  return (
    <RetroCard title="Notificaciones PWA">
      <div className="flex flex-col gap-3">
        <p className="text-[0.625rem] text-text-muted">
          Recibe alertas directamente en tu dispositivo Android o PC.
        </p>
        
        <div className="flex items-center justify-between gap-4 border-b-2 border-black pb-3">
          <div className="flex items-center gap-2">
            {subscription ? <Bell className="text-success" size={16} /> : <BellOff className="text-text-muted" size={16} />}
            <span className="text-xs font-black uppercase">
              {subscription ? 'Activadas' : 'Desactivadas'}
            </span>
          </div>
          
          {subscription ? (
            <RetroButton variant="secondary" onClick={unsubscribe} className="px-3 py-1 text-[0.625rem]">
              DESACTIVAR
            </RetroButton>
          ) : (
            <RetroButton variant="primary" disabled={isSubscribing} onClick={() => subscribe(enabledEvents)} className="px-3 py-1 text-[0.625rem]">
              {isSubscribing ? '...' : 'ACTIVAR'}
            </RetroButton>
          )}
        </div>

        {subscription && (
          <div className="flex flex-col gap-2">
            <div className="flex items-center gap-1.5 text-[0.5625rem] font-black uppercase text-text-muted">
              <Settings2 size={12} />
              Configurar eventos
            </div>
            
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
              {(Object.entries({
                disconnect: 'Desconexiones',
                bridge: 'Estado Bridge',
                alert: 'Alertas WS'
              }) as [keyof typeof enabledEvents, string][]).map(([key, label]) => (
                <label key={key} className="flex cursor-pointer items-center justify-between border-2 border-black bg-bg-primary px-2 py-1.5 hover:bg-accent/5">
                  <span className="text-[0.625rem] font-bold uppercase">{label}</span>
                  <input
                    type="checkbox"
                    checked={enabledEvents[key]}
                    onChange={() => toggleEvent(key)}
                    className="h-3 w-3 accent-accent"
                  />
                </label>
              ))}
            </div>
          </div>
        )}
      </div>
    </RetroCard>
  );
};
