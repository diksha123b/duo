// Duo's service worker: shows push notifications even when the tab is closed,
// and opens the right screen when one is tapped.
self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = { title: 'duo', body: event.data ? event.data.text() : '' };
  }
  event.waitUntil(
    self.registration.showNotification(data.title || 'duo', {
      body: data.body || '',
      tag: data.tag,
      renotify: Boolean(data.tag),
      icon: 'icons/Icon-192.png',
      badge: 'icons/Icon-maskable-192.png',
      data: { url: data.url || '/' },
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = new URL(event.notification.data.url || '/', self.registration.scope).href;
  event.waitUntil(
    (async () => {
      const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      // Reuse an open Duo tab if there is one.
      for (const client of windows) {
        if (client.url.startsWith(self.registration.scope)) {
          await client.focus();
          return client.navigate(target);
        }
      }
      return self.clients.openWindow(target);
    })(),
  );
});
