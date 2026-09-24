// =========================================================
//  m3u.js — Chargement/parsing d'une playlist M3U
// =========================================================
//  On télécharge le fichier .m3u et on extrait les chaînes (#EXTINF) avec leur
//  nom, logo (tvg-logo), groupe (group-title) et URL de flux.
// =========================================================
window.DFT = window.DFT || {};

DFT.m3u = (function () {
  function attr(line, key) {
    var m = line.match(new RegExp(key + '="([^"]*)"', 'i'));
    return m ? m[1] : '';
  }

  function parse(text) {
    var lines = String(text || '').split(/\r?\n/);
    var channels = [];
    var pending = null;
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      if (line.indexOf('#EXTINF') === 0) {
        var comma = line.lastIndexOf(',');
        pending = {
          name: comma > -1 ? line.substring(comma + 1).trim() : 'Chaîne',
          logo: attr(line, 'tvg-logo'),
          category: attr(line, 'group-title') || 'Autres',
          url: '',
        };
      } else if (line && line.charAt(0) !== '#' && pending) {
        pending.url = line;
        channels.push(pending);
        pending = null;
      }
    }
    return channels;
  }

  function load(src) {
    var url = src.m3u_url || src.url;
    return rawText(url).then(function (t) { return { channels: parse(t) }; });
  }

  function rawText(url) {
    return new Promise(function (resolve, reject) {
      var xhr = new XMLHttpRequest();
      xhr.open('GET', url, true);
      xhr.timeout = DFT.config.httpTimeout;
      xhr.onreadystatechange = function () {
        if (xhr.readyState !== 4) return;
        if (xhr.status >= 200 && xhr.status < 300) resolve(xhr.responseText || '');
        else reject(new Error('HTTP ' + xhr.status));
      };
      xhr.ontimeout = function () { reject(new Error('timeout')); };
      xhr.onerror = function () { reject(new Error('network')); };
      xhr.send(null);
    });
  }

  return { parse: parse, load: load };
})();
