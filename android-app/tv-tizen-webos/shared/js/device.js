// =========================================================
//  device.js — Identité stable de l'appareil (MAC « MK:… »)
// =========================================================
//  Le backend identifie chaque appareil par une MAC virtuelle au format
//  MK:XX:XX:XX:XX:XX (5 octets + préfixe MK), comme les apps Android. Ici on la
//  dérive de l'identité matérielle de la TV (MAC réelle Tizen / device-id
//  webOS), de façon DÉTERMINISTE et STABLE :
//    1) si une MAC a déjà été mémorisée (localStorage) → on la garde À VIE.
//    2) sinon on la dérive (FNV-1a) de l'identifiant matériel → même TV =
//       même MAC, même après réinstallation.
//    3) en tout dernier recours : aléatoire (puis mémorisée).
// =========================================================
window.DFT = window.DFT || {};

DFT.device = (function () {
  var STORE_KEY = 'dft.virtual_mac.v1';

  // FNV-1a 32 bits → on étale sur 5 octets pour fabriquer la MAC.
  function macFromSeed(seed) {
    var h = 0x811c9dc5;
    for (var i = 0; i < seed.length; i++) {
      h ^= seed.charCodeAt(i);
      h = (h + ((h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24))) >>> 0;
    }
    var bytes = [];
    for (var b = 0; b < 5; b++) {
      bytes.push((h >>> (b * 5)) & 0xff);
      // re-mélange pour décorréler les octets successifs.
      h = (h * 16777619) >>> 0;
    }
    return format(bytes);
  }

  function randomMac() {
    var bytes = [];
    for (var i = 0; i < 5; i++) bytes.push(Math.floor(Math.random() * 256));
    return format(bytes);
  }

  function format(bytes) {
    var parts = ['MK'];
    for (var i = 0; i < bytes.length; i++) {
      var hex = bytes[i].toString(16).toUpperCase();
      if (hex.length < 2) hex = '0' + hex;
      parts.push(hex);
    }
    return parts.join(':');
  }

  function readStored() {
    try { return window.localStorage.getItem(STORE_KEY); } catch (e) { return null; }
  }
  function writeStored(mac) {
    try { window.localStorage.setItem(STORE_KEY, mac); } catch (e) { /* ignore */ }
  }

  // Récupère un identifiant matériel STABLE selon la plateforme (asynchrone).
  function hardwareSeed(cb) {
    // --- Samsung Tizen : MAC réelle via webapis.network, sinon systeminfo ---
    if (DFT.platform === 'tizen') {
      try {
        if (window.webapis && webapis.network && webapis.network.getMac) {
          var mac = webapis.network.getMac();
          if (mac) return cb(String(mac));
        }
      } catch (e) { /* continue */ }
      try {
        if (window.tizen && tizen.systeminfo) {
          tizen.systeminfo.getPropertyValue('WIFI_NETWORK', function (w) {
            if (w && w.macAddress) return cb(String(w.macAddress));
            cb(null);
          }, function () { cb(null); });
          return;
        }
      } catch (e2) { /* continue */ }
      return cb(null);
    }
    // --- LG webOS : device-id via le service Luna ---
    if (DFT.platform === 'webos') {
      try {
        if (window.webOS && webOS.service && webOS.service.request) {
          webOS.service.request('luna://com.webos.service.sm', {
            method: 'deviceid/getIDs',
            parameters: { idType: ['LGUDID'] },
            onSuccess: function (res) {
              var id = res && res.idList && res.idList[0] && res.idList[0].idValue;
              cb(id ? String(id) : null);
            },
            onFailure: function () { cb(null); },
          });
          return;
        }
      } catch (e) { /* continue */ }
      return cb(null);
    }
    return cb(null);
  }

  var _cached = null;

  // Renvoie (async) la MAC stable de cet appareil.
  function getMac(cb) {
    if (_cached) return cb(_cached);
    var stored = readStored();
    if (stored) { _cached = stored; return cb(stored); }
    hardwareSeed(function (seed) {
      var mac = seed ? macFromSeed(seed) : randomMac();
      writeStored(mac);
      _cached = mac;
      cb(mac);
    });
  }

  // Infos appareil (modèle, marque) pour le recensement panel.
  function info() {
    var model = '';
    var brand = DFT.platform === 'tizen' ? 'Samsung'
              : DFT.platform === 'webos' ? 'LG' : 'Web';
    try {
      if (DFT.platform === 'webos' && window.webOS && webOS.deviceInfo) {
        webOS.deviceInfo(function (d) { model = (d && d.modelName) || ''; });
      }
    } catch (e) { /* ignore */ }
    return { model: model || (brand + ' TV'), brand: brand };
  }

  return { getMac: getMac, info: info };
})();
