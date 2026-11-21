// Copyright (c) 2026 Eirini Konidari. All rights reserved.
// Netherlanded Offline Service Worker (v2.1, root-scoped)
// Network-first for same-origin static GET shell assets with offline fallback.
// Never caches /api/ routes or no-store/private responses.
// Notification clicks strictly validate same-origin URLs (SECURITY_AUDIT.md Finding #5).

const CACHE = 'netherlanded-v2.1';
const SHELL = ['./netherlanded-app.html', './web/manifest.webmanifest', './web/icon.svg'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then(async (c) => {
      await Promise.allSettled(SHELL.map((u) => c.add(u)));
    }).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  if (url.pathname.startsWith('/api/') || url.pathname.includes('/api/')) return;
  if (req.headers.has('authorization')) return;

  event.respondWith(
    fetch(req)
      .then((resp) => {
        const cc = (resp.headers.get('cache-control') || '').toLowerCase();
        if (resp && resp.ok && resp.type === 'basic' && !cc.includes('no-store') && !cc.includes('private')) {
          const clone = resp.clone();
          caches.open(CACHE).then((c) => c.put(req, clone)).catch(() => {});
        }
        return resp;
      })
      .catch(() => caches.match(req).then((hit) => hit || Response.error()))
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const raw = (event.notification && event.notification.data && event.notification.data.url) || './netherlanded-app.html';
  let targetUrl;
  try {
    const parsed = new URL(String(raw), self.location.href);
    if (parsed.origin !== self.location.origin) return;
    targetUrl = parsed.href;
  } catch (_) {
    return;
  }

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clients) => {
      for (const client of clients) {
        if (client.url.startsWith(self.location.origin) && 'focus' in client) {
          client.navigate(targetUrl).catch(() => {});
          return client.focus();
        }
      }
      return self.clients.openWindow(targetUrl);
    })
  );
});
