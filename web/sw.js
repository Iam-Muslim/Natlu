// Service Worker for Recite Quran (اتلو القران)
// Provides full offline capability and COOP/COEP Cross-Origin Isolation for WebAssembly.

const CACHE_NAME = 'recite-quran-pwa-v1';

const STATIC_PRECACHE = [
  './',
  'index.html',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'sherpa-onnx-asr.js?v=2',
  'sherpa_official_app.js?v=2',
  'sherpa-onnx-wasm-main-asr.js?v=2',
  'sherpa-onnx-wasm-main-asr.wasm'
];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      console.log('[SW] Precaching essential static assets for offline use...');
      return cache.addAll(STATIC_PRECACHE).catch((err) => {
        console.warn('[SW] Some precache items skipped:', err);
      });
    })
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.map((key) => {
          if (key !== CACHE_NAME) {
            console.log('[SW] Removing old cache:', key);
            return caches.delete(key);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

function addCoopCoepHeaders(response) {
  if (!response || response.status === 0 || response.type === 'opaque') {
    return response;
  }
  const newHeaders = new Headers(response.headers);
  newHeaders.set('Cross-Origin-Opener-Policy', 'same-origin');
  newHeaders.set('Cross-Origin-Embedder-Policy', 'credentialless');
  newHeaders.set('Cross-Origin-Resource-Policy', 'cross-origin');

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers: newHeaders
  });
}

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // 1. Never cache the raw model download endpoint in Service Worker (it is stored in IndexedDB)
  if (url.pathname.includes('/download-model')) {
    return;
  }

  // 2. Navigation requests (HTML pages): Network First, fallback to cached index.html
  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request)
        .then((networkResponse) => {
          const cloned = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, cloned));
          return addCoopCoepHeaders(networkResponse);
        })
        .catch(async () => {
          const cached = await caches.match(event.request);
          if (cached) return addCoopCoepHeaders(cached);
          const fallback = await caches.match('index.html') || await caches.match('./');
          return addCoopCoepHeaders(fallback);
        })
    );
    return;
  }

  // 3. Static assets: Cache First, fallback to Network (and cache dynamically)
  event.respondWith(
    caches.match(event.request).then((cachedResponse) => {
      if (cachedResponse) {
        return addCoopCoepHeaders(cachedResponse);
      }

      return fetch(event.request).then((networkResponse) => {
        if (networkResponse && networkResponse.status === 200 && event.request.method === 'GET') {
          const responseToCache = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, responseToCache);
          });
        }
        return addCoopCoepHeaders(networkResponse);
      }).catch((fetchErr) => {
        // If offline and not in cache, let it fail gracefully
        return cachedResponse;
      });
    })
  );
});
