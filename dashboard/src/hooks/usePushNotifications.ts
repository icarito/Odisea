import { useState, useEffect } from 'react';
import { getVapidKey, subscribePush } from '../api';
import { toast } from 'react-hot-toast';

function urlBase64ToUint8Array(base64String: string) {
  const padding = '='.repeat((4 - base64String.length % 4) % 4);
  const base64 = (base64String + padding)
    .replace(/-/g, '+')
    .replace(/_/g, '/');

  const rawData = window.atob(base64);
  const outputArray = new Uint8Array(rawData.length);

  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}

export function usePushNotifications() {
  const [subscription, setSubscription] = useState<PushSubscription | null>(null);
  const [isSupported, setIsSupported] = useState(false);
  const [permission, setPermission] = useState<NotificationPermission>('default');
  const [vapidKey, setVapidKey] = useState<string | null>(null);
  const [isSubscribing, setIsSubscribing] = useState(false);

  useEffect(() => {
    if ('serviceWorker' in navigator && 'PushManager' in window) {
      setIsSupported(true);
      setPermission(Notification.permission);
      
      // Pre-fetch VAPID key so subscribe() doesn't break the user gesture chain
      getVapidKey().then(({ publicKey }: any) => {
        if (publicKey) setVapidKey(publicKey);
      }).catch(() => {});
      
      navigator.serviceWorker.ready.then(registration => {
        registration.pushManager.getSubscription().then(sub => {
          setSubscription(sub);
        });
      });
    }
  }, []);

  const subscribe = async (settings: any = {}) => {
    if (isSubscribing) return;
    
    // Permission must be requested FIRST to preserve user gesture
    if (Notification.permission !== 'granted') {
      const result = await Notification.requestPermission();
      setPermission(result);
      if (result !== 'granted') {
        toast.error("Permiso de notificaciones denegado");
        return;
      }
    }
    
    setIsSubscribing(true);
    try {
      const reg = await navigator.serviceWorker.ready;
      
      const publicKey = vapidKey;
      if (!publicKey) throw new Error("No VAPID public key received from server");

      // Called immediately after user gesture — no await between click and subscribe
      const sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(publicKey)
      });

      await subscribePush(sub, settings);
      setSubscription(sub);
      setPermission(Notification.permission);
      toast.success("Notificaciones activadas");
    } catch (e) {
      console.error("Failed to subscribe to push notifications", e);
      toast.error("Error al activar notificaciones");
    } finally {
      setIsSubscribing(false);
    }
  };

  const unsubscribe = async () => {
    if (!subscription) return;
    try {
      await subscription.unsubscribe();
      setSubscription(null);
      toast.success("Notificaciones desactivadas");
    } catch (e) {
      console.error("Failed to unsubscribe", e);
    }
  };

  return { subscription, isSupported, permission, isSubscribing, subscribe, unsubscribe };
}
