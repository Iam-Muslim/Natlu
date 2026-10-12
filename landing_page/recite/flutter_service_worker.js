// Neutralized: Custom PWA service worker is managed by sw.js
// Do not unregister or replace sw.js
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', () => self.clients.claim());
