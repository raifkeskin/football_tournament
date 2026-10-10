// Web Push service worker. Flutter'ın kendi service worker'ı kök kapsamda
// kendini sildiği için bu dosya ayrı kapsamla ("/push/") kaydedilir.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = { title: 'Master Futbol', body: event.data ? event.data.text() : '' };
  }
  event.waitUntil(
    self.registration.showNotification(data.title || 'Master Futbol', {
      body: data.body || '',
      icon: '/icons/Icon-maskable-192.png',
      badge: '/icons/Icon-maskable-192.png',
      tag: data.tag || undefined,
      data: { url: data.url || '/' },
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = new URL((event.notification.data && event.notification.data.url) || '/', self.location.origin).href;
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        if (c.url.startsWith(self.location.origin) && 'focus' in c) {
          // Açık uygulama ilgili ekranı kendisi açar.
          c.postMessage({ type: 'push-open', url });
          return c.focus();
        }
      }
      return self.clients.openWindow(url);
    }),
  );
});
