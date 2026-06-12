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

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList: any) => {
      if (clientList.length > 0) {
        let client = clientList[0];
        for (let i = 0; i < clientList.length; i++) {
          if (clientList[i].focused) {
            client = clientList[i];
            break;
          }
        }
        return client.focus();
      }
      return self.clients.openWindow('/');
    })
  );
});
