// =========================================================
//  api.js — Client du backend (MÊMES routes publiques que les apps Android)
// =========================================================
//    POST /api/heartbeat        → crée/raffraîchit l'appareil, renvoie le statut
//    GET  /api/status/:mac      → statut d'abonnement
//    GET  /api/device-source/:mac → source IPTV poussée par le panel (trio)
// =========================================================
window.DFT = window.DFT || {};

DFT.api = (function () {
  function base() { return DFT.config.apiBase; }

  // Petit fetch avec timeout (les TV ont parfois un réseau capricieux).
  function http(method, url, body) {
    return new Promise(function (resolve, reject) {
      var done = false;
      var xhr = new XMLHttpRequest();
      xhr.open(method, url, true);
      xhr.timeout = DFT.config.httpTimeout;
      xhr.setRequestHeader('Accept', 'application/json');
      if (body) xhr.setRequestHeader('Content-Type', 'application/json');
      xhr.onreadystatechange = function () {
        if (xhr.readyState !== 4 || done) return;
        done = true;
        if (xhr.status >= 200 && xhr.status < 300) {
          try { resolve(JSON.parse(xhr.responseText || 'null')); }
          catch (e) { resolve(null); }
        } else {
          reject(new Error('HTTP ' + xhr.status));
        }
      };
      xhr.ontimeout = function () { if (!done) { done = true; reject(new Error('timeout')); } };
      xhr.onerror = function () { if (!done) { done = true; reject(new Error('network')); } };
      xhr.send(body ? JSON.stringify(body) : null);
    });
  }

  function heartbeat(mac, info) {
    var payload = {
      mac: mac,
      model: (info && info.model) || '',
      manufacturer: (info && info.brand) || '',
      platform: 'tv',
      appVersion: '1.0.0',
      channel: '',
    };
    return http('POST', base() + '/api/heartbeat', payload);
  }

  function status(mac) {
    return http('GET', base() + '/api/status/' + encodeURIComponent(mac));
  }

  function deviceSource(mac) {
    return http('GET', base() + '/api/device-source/' + encodeURIComponent(mac));
  }

  return { http: http, heartbeat: heartbeat, status: status, deviceSource: deviceSource };
})();
