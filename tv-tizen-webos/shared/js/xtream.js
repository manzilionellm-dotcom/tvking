// =========================================================
//  xtream.js — Chargement des chaînes via une source Xtream Codes
// =========================================================
//  À partir de {server, username, password} on récupère catégories + chaînes
//  Live, et on fabrique l'URL de flux. On ne garde que le LIVE (cette app est
//  un lecteur de télévision en direct).
// =========================================================
window.DFT = window.DFT || {};

DFT.xtream = (function () {
  // Normalise l'URL serveur (ajoute http:// si absent, retire le / final).
  function normServer(s) {
    var u = String(s || '').trim();
    if (!/^https?:\/\//i.test(u)) u = 'http://' + u;
    return u.replace(/\/+$/, '');
  }

  function api(server, user, pass, action, extra) {
    var url = normServer(server) + '/player_api.php?username=' +
      encodeURIComponent(user) + '&password=' + encodeURIComponent(pass) +
      '&action=' + action + (extra || '');
    return DFT.api.http('GET', url, null);
  }

  // Charge catégories + chaînes Live et renvoie { categories, channels }.
  function load(src) {
    var server = normServer(src.server_url || src.server);
    var user = src.username;
    var pass = src.password;
    var ext = DFT.config.streamExt;

    return Promise.all([
      api(server, user, pass, 'get_live_categories'),
      api(server, user, pass, 'get_live_streams'),
    ]).then(function (res) {
      var cats = res[0] || [];
      var streams = res[1] || [];
      var catName = {};
      for (var i = 0; i < cats.length; i++) {
        catName[String(cats[i].category_id)] = cats[i].category_name || 'Autres';
      }
      var channels = [];
      for (var j = 0; j < streams.length; j++) {
        var s = streams[j];
        var id = s.stream_id;
        if (id == null) continue;
        channels.push({
          name: s.name || ('Chaîne ' + id),
          logo: s.stream_icon || '',
          category: catName[String(s.category_id)] || 'Autres',
          url: server + '/live/' + encodeURIComponent(user) + '/' +
               encodeURIComponent(pass) + '/' + id + '.' + ext,
        });
      }
      return { channels: channels };
    });
  }

  return { load: load };
})();
