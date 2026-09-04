// Service Worker for Natlu / Recite Quran Landing Page
// Provides instant loading and 100% offline caching to save bandwidth
const CACHE_NAME = 'natlu-landing-v2';

const ASSETS_TO_CACHE = [
  './',
  'index.html',
  'app_icon.png',
  'favicon.png',
  'apple-touch-icon.png',
  'assets/qamar.png',
  'assets/fatiha.png',
  'assets/yusuf.png',
  'assets/search.png',
  'assets/ahzab.png',
  'assets/badges/google_play.svg',
  'assets/badges/app_store.svg',
  'assets/badges/web_app.svg'
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => {
      return cache.addAll(ASSETS_TO_CACHE);
    }).then(() => self.skipWaiting())
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

// Cache-First Strategy for Images & Static Assets (Zero bandwidth on repeat visits)
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);

  // Serve static assets from cache first
  if (
    url.pathname.includes('/assets/') ||
    url.pathname.endsWith('.png') ||
    url.pathname.endsWith('.svg') ||
    url.pathname.endsWith('.jpg') ||
    url.pathname.endsWith('.woff2')
  ) {
    event.respondWith(
      caches.match(event.request).then(cachedResponse => {
        if (cachedResponse) {
          return cachedResponse;
        }
        return fetch(event.request).then(networkResponse => {
          if (networkResponse && networkResponse.status === 200) {
            const responseClone = networkResponse.clone();
            caches.open(CACHE_NAME).then(cache => {
              cache.put(event.request, responseClone);
            });
          }
          return networkResponse;
        });
      })
    );
    return;
  }

  // Network-first for HTML pages with cache fallback
  event.respondWith(
    fetch(event.request).then(networkResponse => {
      if (networkResponse && networkResponse.status === 200) {
        const responseClone = networkResponse.clone();
        caches.open(CACHE_NAME).then(cache => {
          cache.put(event.request, responseClone);
        });
      }
      return networkResponse;
    }).catch(() => caches.match(event.request))
  );
});
