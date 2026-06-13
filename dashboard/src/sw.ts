/// <reference lib="webworker" />
import { precacheAndRoute, cleanupOutdatedCaches } from 'workbox-precaching';
import { registerRoute } from 'workbox-routing';
import { NetworkFirst } from 'workbox-strategies';

declare const self: ServiceWorkerGlobalScope & {
  __WB_MANIFEST: any[];
};

cleanupOutdatedCaches();
precacheAndRoute(self.__WB_MANIFEST);

// Basic runtime caching for API calls (fallback to NetworkFirst to allow offline snapshot usage in the app)
registerRoute(
  ({ url }) => url.pathname.startsWith('/status') || url.pathname.startsWith('/health'),
  new NetworkFirst({
    cacheName: 'api-cache',
  })
);

self.addEventListener('push', (event) => {
  if (!event.data) return;

  try {
    const data = event.data.json();
    const title = 'Odisea Dashboard';
    const options: NotificationOptions = {
      body: data.message || 'Alerta de Odisea',
      icon: '/pwa-192x192.png',
      badge: '/favicon.svg',
      data: data,
    };

    event.waitUntil(self.registration.showNotification(title, options));
  } catch (e) {
    console.error('Error handling push event', e);
  }
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const data = event.notification?.data || {};
  const playerId = data.playerId || data.player_id || '';
  const sessionId = data.sessionId || data.session_id || '';
  const params = new URLSearchParams();
  if (playerId) params.set('player', String(playerId));
  if (sessionId) params.set('session', String(sessionId));
  const qs = params.toString();
  const targetUrl = qs ? `/?${qs}` : '/';

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList: any) => {
      // Try to focus an existing window and navigate it to the target URL
      for (const client of clientList) {
        if ('navigate' in client) {
          (client as any).navigate(targetUrl);
          return client.focus();
        }
      }
      return self.clients.openWindow(targetUrl);
    })
  );
});
