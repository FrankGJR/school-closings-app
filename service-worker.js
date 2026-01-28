const CACHE_NAME = 'school-closings-v8';
const URLS_TO_CACHE = [
    '/',
    '/index.html',
    '/styles.css',
    '/app.js',
    '/manifest.json'
];

// Install Service Worker
self.addEventListener('install', event => {
    event.waitUntil(
        caches.open(CACHE_NAME)
            .then(cache => {
                return cache.addAll(URLS_TO_CACHE).catch(err => {
                    console.log('Cache addAll error:', err);
                    // Don't fail on cache errors
                });
            })
            .catch(err => console.log('Cache open error:', err))
    );
    self.skipWaiting();
});

// Activate Service Worker
self.addEventListener('activate', event => {
    event.waitUntil(
        caches.keys().then(cacheNames => {
            return Promise.all(
                cacheNames.map(cacheName => {
                    if (cacheName !== CACHE_NAME) {
                        return caches.delete(cacheName);
                    }
                })
            );
        })
    );
    self.clients.claim();
});

// Fetch Event - Network first for API, cache first for assets
self.addEventListener('fetch', event => {
    const { request } = event;
    const url = new URL(request.url);

    // Ignore API requests completely—let them go straight to the network
    if (url.hostname.includes('execute-api.amazonaws.com')) {
        return;
    }

    // Assets - cache first, fall back to network
    event.respondWith(
        caches.match(request)
            .then(cachedResponse => {
                if (cachedResponse) {
                    return cachedResponse;
                }
                return fetch(request)
                    .then(response => {
                        if (!response || response.status !== 200 || response.type === 'error') {
                            return response;
                        }

                        const responseClone = response.clone();
                        caches.open(CACHE_NAME).then(cache => {
                            cache.put(request, responseClone);
                        });

                        return response;
                    })
                    .catch(() => {
                        // Return offline page if available, or a basic error response
                        return caches.match('/index.html').then(fallback => {
                            return fallback || new Response('Offline', {
                                status: 503,
                                statusText: 'Service Unavailable',
                                headers: new Headers({
                                    'Content-Type': 'text/plain'
                                })
                            });
                        });
                    });
            })
    );
});

// Background sync for when app comes back online
self.addEventListener('sync', event => {
    if (event.tag === 'sync-closings') {
        event.waitUntil(
            fetch('https://yr4zm4dy27.execute-api.us-east-1.amazonaws.com/Prod/')
                .then(response => response.json())
                .then(data => {
                    // Notify clients of updated data
                    self.clients.matchAll().then(clients => {
                        clients.forEach(client => {
                            client.postMessage({
                                type: 'CLOSINGS_UPDATED',
                                data: data
                            });
                        });
                    });
                })
        );
    }
});
