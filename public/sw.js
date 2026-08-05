/*
 * Service worker TV King — l'assurance anti-écran-blanc des box.
 *
 * Un box TV redémarre l'app avec un réseau souvent lent ou pas encore prêt :
 * sans cache, le WebView n'a RIEN à afficher (écran blanc). Stratégie :
 *  - navigations : réseau d'abord (les mises à jour passent), cache en
 *    secours, et à défaut la coquille d'accueil pré-cachée ;
 *  - assets /_next/static (hachés, immuables) : cache d'abord.
 *
 * Écrit en ES5 : ce fichier n'est PAS transpilé par Next (public/), il doit
 * se parser tel quel sur les WebView anciens.
 */

var CACHE = "tvking-shell-v1";

self.addEventListener("install", function (event) {
  self.skipWaiting();
  event.waitUntil(
    caches
      .open(CACHE)
      .then(function (cache) {
        // La coquille = la racine de l'app (scope du SW), pour avoir au moins
        // un écran utilisable hors-ligne même sans navigation préalable.
        return cache.add(self.registration.scope).catch(function () {});
      })
      .catch(function () {})
  );
});

self.addEventListener("activate", function (event) {
  event.waitUntil(
    caches
      .keys()
      .then(function (keys) {
        return Promise.all(
          keys
            .filter(function (k) {
              return k.indexOf("tvking-") === 0 && k !== CACHE;
            })
            .map(function (k) {
              return caches.delete(k);
            })
        );
      })
      .then(function () {
        return self.clients.claim();
      })
  );
});

function putInCache(request, response) {
  var copy = response.clone();
  caches
    .open(CACHE)
    .then(function (cache) {
      cache.put(request, copy);
    })
    .catch(function () {});
}

self.addEventListener("fetch", function (event) {
  var request = event.request;
  if (request.method !== "GET") return;
  var url;
  try {
    url = new URL(request.url);
  } catch (e) {
    // Le paramètre de catch est obligatoire sur les WebView < Chrome 66.
    void e;
    return;
  }
  if (url.origin !== self.location.origin) return;

  // Navigation (HTML) : réseau d'abord, cache en secours, coquille en dernier.
  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request)
        .then(function (response) {
          if (response && response.ok) putInCache(request, response);
          return response;
        })
        .catch(function () {
          return caches.match(request).then(function (hit) {
            return hit || caches.match(self.registration.scope);
          });
        })
    );
    return;
  }

  // Assets : cache d'abord (les fichiers _next/static sont hachés).
  event.respondWith(
    caches.match(request).then(function (hit) {
      if (hit) return hit;
      return fetch(request).then(function (response) {
        if (response && response.ok) putInCache(request, response);
        return response;
      });
    })
  );
});
