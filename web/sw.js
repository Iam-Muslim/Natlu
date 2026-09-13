// Service Worker for Recite Quran (اتلو القران)
// Provides offline precaching, dynamic caching, and Cross-Origin Isolation (COOP/COEP) for WebAssembly.

const CACHE_NAME = 'recite-quran-pwa-v9';

const STATIC_PRECACHE = [
  './',
  'index.html',
  'manifest.json',
  'favicon.png',
  'icons/apple-touch-icon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'pwa_install.js',
  'audio_worklet.js',
  'sherpa-onnx-asr.js',
  'sherpa_official_app.js',
  'sherpa-onnx-wasm-main-asr.js',
  'sherpa-onnx-wasm-main-asr.wasm',
  'flutter_bootstrap.js',
  'main.dart.js',
  'assets/FontManifest.json',
  'assets/AssetManifest.json',
  'assets/AssetManifest.bin.json',
  'assets/fonts/HafsSmart_08.ttf',
  'assets/packages/recite_quran/assets/model/tokens.txt'
];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) =>
      Promise.allSettled(
        STATIC_PRECACHE.map((url) =>
          cache.add(url).catch((err) => console.warn('[SW] Precache skipped:', url, err))
        )
      )
    )
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

function addCoopCoepHeaders(response) {
  if (!response || response.status === 0 || response.type === 'opaque' || [101, 204, 205, 304].includes(response.status)) {
    return response;
  }
  const headers = new Headers(response.headers);
  headers.set('Cross-Origin-Opener-Policy', 'same-origin');
  headers.set('Cross-Origin-Embedder-Policy', 'credentialless');
  headers.set('Cross-Origin-Resource-Policy', 'cross-origin');

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers
  });
}

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;

  const url = new URL(event.request.url);

  // Model download endpoint is saved directly to IndexedDB
  if (url.pathname.includes('/download-model')) return;

  // 1. Navigation requests: Network First, fallback to cached index.html
  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request)
        .then((res) => {
          if (res && res.status === 200) {
            const clone = res.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
          }
          return addCoopCoepHeaders(res);
        })
        .catch(async () => {
          const cached = (await caches.match(event.request, { ignoreSearch: true })) ||
                         (await caches.match('index.html')) ||
                         (await caches.match('./'));
          return cached ? addCoopCoepHeaders(cached) : Response.error();
        })
    );
    return;
  }

  // 2. Static assets: Cache First, fallback to Network with dynamic caching
  event.respondWith(
    caches.match(event.request, { ignoreSearch: true }).then((cached) => {
      if (cached) return cached;

      return fetch(event.request).then((res) => {
        if (res && res.status === 200) {
          const clone = res.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        }
        return res;
      }).catch(async () => {
        const fallback = await caches.match(url.pathname, { ignoreSearch: true });
        return fallback || Response.error();
      });
    })
  );
});
