
const CACHE_NAME = 'streamflow-v2-cache';
const CACHE_VERSION = '1.0.3';
const FULL_CACHE_NAME = `${CACHE_NAME}-${CACHE_VERSION}`;
const API_CACHE_NAME = `${CACHE_NAME}-api-${CACHE_VERSION}`;
const API_CACHE_TTL = 30 * 1000; // 30 seconds

const STATIC_RESOURCES = [
  'https://cdn.jsdelivr.net/npm/@tabler/icons-webfont@2.30.0/tabler-icons.min.css',
  'https://cdn.jsdelivr.net/npm/@tabler/icons-webfont@2.30.0/fonts/tabler-icons.woff2',
  'https://cdn.jsdelivr.net/npm/@tabler/icons-webfont@2.30.0/fonts/tabler-icons.woff',
  'https://cdn.jsdelivr.net/npm/@tabler/icons-webfont@2.30.0/fonts/tabler-icons.ttf',

  '/css/styles.css',
  '/js/stream-modal.js',

  '/images/logo.svg'
];

// API endpoints to cache (network-first with fallback)
const CACHEABLE_API_PATTERNS = [
  '/api/videos',
  '/api/playlists',
  '/api/streams',
  '/api/settings/youtube-channels'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(FULL_CACHE_NAME)
      .then((cache) => {
        console.log('Service Worker: Caching static resources');
        return cache.addAll(STATIC_RESOURCES);
      })
      .then(() => {
        console.log('Service Worker: All resources cached successfully');
        return self.skipWaiting();
      })
      .catch((error) => {
        console.error('Service Worker: Failed to cache resources', error);
      })
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((cacheNames) => {
        return Promise.all(
          cacheNames.map((cacheName) => {
            if ((cacheName.startsWith(CACHE_NAME) && cacheName !== FULL_CACHE_NAME && cacheName !== API_CACHE_NAME)) {
              console.log('Service Worker: Deleting old cache', cacheName);
              return caches.delete(cacheName);
            }
          })
        );
      })
      .then(() => {
        console.log('Service Worker: Activated');
        return self.clients.claim();
      })
  );
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') {
    return;
  }

  const url = event.request.url;

  // Handle font requests (cache-first)
  const isFontRequest = url.includes('tabler-icons') ||
    url.endsWith('.woff2') ||
    url.endsWith('.woff') ||
    url.endsWith('.ttf');

  if (isFontRequest) {
    event.respondWith(
      caches.match(event.request)
        .then((cachedResponse) => {
          if (cachedResponse) {
            return cachedResponse;
          }
          return fetch(event.request)
            .then((response) => {
              if (!response || response.status !== 200) {
                return response;
              }
              const responseToCache = response.clone();
              caches.open(FULL_CACHE_NAME)
                .then((cache) => {
                  cache.put(event.request, responseToCache);
                });
              return response;
            });
        })
    );
    return;
  }

  // Handle API requests (network-first with cache fallback)
  const isApiRequest = CACHEABLE_API_PATTERNS.some(pattern => url.includes(pattern));

  if (isApiRequest) {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          if (response && response.status === 200) {
            const responseToCache = response.clone();
            caches.open(API_CACHE_NAME)
              .then((cache) => {
                // Store with timestamp
                cache.put(event.request, responseToCache);
              });
          }
          return response;
        })
        .catch(() => {
          // Network failed, try cache
          return caches.match(event.request);
        })
    );
    return;
  }

  // Handle static resources (cache-first)
  if (isStaticResource(url)) {
    event.respondWith(
      caches.match(event.request)
        .then((cachedResponse) => {
          if (cachedResponse) {
            return cachedResponse;
          }

          return fetch(event.request)
            .then((response) => {
              if (!response || response.status !== 200 || response.type !== 'basic' && response.type !== 'cors') {
                return response;
              }

              const responseToCache = response.clone();

              caches.open(FULL_CACHE_NAME)
                .then((cache) => {
                  cache.put(event.request, responseToCache);
                });

              return response;
            })
            .catch((error) => {
              console.error('Service Worker: Fetch failed', error);
              throw error;
            });
        })
    );
  }
});

function isStaticResource(url) {
  return STATIC_RESOURCES.some(resource => url.includes(resource)) ||
    url.includes('tabler-icons') ||
    url.includes('cdn.jsdelivr.net') ||
    url.endsWith('.css') ||
    url.endsWith('.js') ||
    url.endsWith('.woff2') ||
    url.endsWith('.woff') ||
    url.endsWith('.ttf') ||
    url.endsWith('.svg');
}

self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }

  // Clear API cache on demand
  if (event.data && event.data.type === 'CLEAR_API_CACHE') {
    caches.delete(API_CACHE_NAME)
      .then(() => {
        console.log('Service Worker: API cache cleared');
      });
  }
});