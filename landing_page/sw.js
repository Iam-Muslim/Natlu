// Service Worker for Natlu / Recite Quran Landing Page
// Provides instant loading and 100% offline caching to save bandwidth
const CACHE_NAME = 'natlu-landing-v18-1792016698';

const ASSETS_TO_CACHE = [
  './',
  'index.html',
  'app_icon.png',
  'favicon.png',
  'apple-touch-icon.png',
  'screenshots/1.png?v=2',
  'screenshots/2.png?v=2',
  'screenshots/3.png?v=2',
  'screenshots/4.png?v=2',
  'ReciteQuran.png'
];

self.addEventListener('install', event => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache =>
      Promise.allSettled(
        ASSETS_TO_CACHE.map(url =>
          cache.add(url).catch(err => console.warn('[SW-Landing] Precache skipped:', url, err))
        )
      )
    )
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys => {
      return Promise.all(
        keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key))
      );
    }).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);

  // CRITICAL: Do NOT intercept /recite/ requests.
  // The Flutter Web App at /recite/ has its own dedicated Service Worker and Cache Storage.
  if (url.pathname.startsWith('/recite')) {
    return;
  }

  // 1. Navigation requests: Network-First with cache fallback
  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request)
        .then(networkResponse => {
          if (networkResponse && networkResponse.status === 200) {
            const responseClone = networkResponse.clone();
            caches.open(CACHE_NAME).then(cache => cache.put(event.request, responseClone));
          }
          return networkResponse;
        })
        .catch(async () => {
          const cached = (await caches.match(event.request, { ignoreSearch: true })) ||
                         (await caches.match('index.html')) ||
                         (await caches.match('./'));
          return cached || Response.error();
        })
    );
    return;
  }

  // 2. Static Assets: Stale-While-Revalidate with network update
  event.respondWith(
    caches.match(event.request).then(cachedResponse => {
      const fetchPromise = fetch(event.request).then(networkResponse => {
        if (networkResponse && networkResponse.status === 200) {
          const responseClone = networkResponse.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(event.request, responseClone));
        }
        return networkResponse;
      }).catch(() => cachedResponse);

      return cachedResponse || fetchPromise;
    })
  );
});
