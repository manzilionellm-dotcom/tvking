// landing.js — page d'accueil premium 7 MOTION servie sur la racine /.
// Source ÉDITABLE : marketing/website/index.html — régénérer après modif.
export function landingHtml() {
  return `<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>7 MOTION — L'expérience télé, sereine et premium</title>
<meta name="description" content="7 MOTION : un lecteur premium, fluide et sans coupure, pour téléphone et TV. Activation en minutes, accompagnement humain, sérénité totale." />
<style>
  /* ===========================================================
     7 MOTION — Thème PREMIUM. Noir profond + Or. Retenue & confiance.
     =========================================================== */
  :root{
    --bg:#050506;            /* noir profond, dramatique */
    --bg-soft:#0a0a0c;
    --panel:rgba(255,255,255,.035);
    --panel-2:rgba(255,255,255,.06);
    --line:rgba(255,255,255,.09);
    --line-gold:rgba(214,176,94,.35);
    --gold:#d8b766;          /* or — couleur d'action VIP */
    --gold-bright:#ecd08a;
    --red:#e0202e;           /* accent marque, employé avec parcimonie */
    --text:#f4f2ec;          /* blanc chaud */
    --muted:#a09d92;         /* gris chaud */
    --radius:20px; --maxw:1140px;
    --serif:"Hoefler Text","Iowan Old Style",Garamond,"Palatino Linotype","Times New Roman",serif;
    --sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
  }
  *{box-sizing:border-box;margin:0;padding:0}
  html{scroll-behavior:smooth}
  body{
    background:var(--bg); color:var(--text); font-family:var(--sans);
    line-height:1.6; -webkit-font-smoothing:antialiased; overflow-x:hidden;
    /* Lumière douce, ambiance feutrée (showroom de luxe) */
    background-image:
      radial-gradient(120% 80% at 50% -10%, rgba(216,183,102,.10), transparent 55%),
      radial-gradient(90% 60% at 85% 8%, rgba(224,32,46,.06), transparent 60%);
    background-attachment:fixed;
  }
  a{color:inherit;text-decoration:none}
  .wrap{max-width:var(--maxw);margin:0 auto;padding:0 22px}
  section{padding:86px 0;position:relative}
  .eyebrow{display:inline-block;color:var(--gold);font-size:12.5px;font-weight:700;
    letter-spacing:3.5px;text-transform:uppercase;margin-bottom:18px}
  h1,h2{font-family:var(--serif);font-weight:600;letter-spacing:-.4px;line-height:1.08}
  h2{font-size:clamp(28px,4.4vw,42px)}
  h2 .g{color:var(--gold)}
  .lead{color:var(--muted);font-size:clamp(16px,2.1vw,19px);max-width:600px}
  .center{text-align:center;margin-inline:auto}

  /* ---- Boutons ---- */
  .btn{display:inline-flex;align-items:center;justify-content:center;gap:10px;
    padding:16px 30px;border-radius:999px;font-weight:700;font-size:16px;
    cursor:pointer;border:none;transition:.25s ease;white-space:nowrap;font-family:var(--sans)}
  .btn:active{transform:scale(.98)}
  /* Or = action principale (sur noir, l'or « appelle le clic ») */
  .btn-gold{background:linear-gradient(135deg,var(--gold-bright),var(--gold));color:#1c1606;
    font-weight:800;box-shadow:0 10px 34px rgba(216,183,102,.28)}
  .btn-gold:hover{transform:translateY(-2px);box-shadow:0 16px 50px rgba(216,183,102,.42)}
  .btn-ghost{background:transparent;color:var(--text);border:1px solid var(--line)}
  .btn-ghost:hover{border-color:var(--gold);color:var(--gold-bright)}

  /* ---- Nav ---- */
  header.nav{position:sticky;top:0;z-index:50;background:rgba(5,5,6,.72);
    backdrop-filter:blur(16px);border-bottom:1px solid var(--line)}
  .nav-in{display:flex;align-items:center;justify-content:space-between;height:70px}
  .logo{font-weight:800;font-size:22px;letter-spacing:2px}
  .logo b{color:var(--red)}
  .nav-links{display:flex;gap:30px;font-size:14.5px;color:var(--muted)}
  .nav-links a:hover{color:var(--text)}
  @media(max-width:820px){.nav-links{display:none}}
  .btn-nav{padding:12px 22px;font-size:14.5px}

  /* ---- Hero ---- */
  .hero{padding:96px 0 70px;text-align:center}
  .hero h1{font-size:clamp(40px,7.2vw,72px);margin:6px 0 0}
  .hero h1 .accent{color:var(--gold)}
  .hero .lead{margin:22px auto 32px}
  .hero-cta{display:flex;gap:14px;justify-content:center;flex-wrap:wrap}
  .reassure{margin-top:26px;color:var(--muted);font-size:14px;display:flex;gap:10px 22px;
    justify-content:center;flex-wrap:wrap}
  .reassure span{display:inline-flex;align-items:center;gap:7px}
  .dot{width:6px;height:6px;border-radius:50%;background:var(--gold);display:inline-block}

  /* ---- Bande confiance ---- */
  .trust{border-top:1px solid var(--line);border-bottom:1px solid var(--line);
    background:rgba(255,255,255,.015)}
  .trust .grid{display:grid;grid-template-columns:repeat(4,1fr);gap:26px}
  .trust .item{text-align:center}
  .trust .tk{width:46px;height:46px;border-radius:14px;margin:0 auto 12px;
    display:flex;align-items:center;justify-content:center;font-size:20px;
    background:rgba(216,183,102,.10);border:1px solid var(--line-gold);color:var(--gold-bright)}
  .trust h3{font-size:16px;font-weight:700;margin-bottom:3px}
  .trust p{color:var(--muted);font-size:13.5px}
  @media(max-width:760px){.trust .grid{grid-template-columns:repeat(2,1fr);gap:30px 20px}}

  /* ---- Cartes / grilles ---- */
  .grid{display:grid;gap:18px}
  .g3{grid-template-columns:repeat(3,1fr)}
  @media(max-width:820px){.g3{grid-template-columns:1fr}}
  .card{background:var(--panel);border:1px solid var(--line);border-radius:var(--radius);
    padding:30px;transition:.25s;backdrop-filter:blur(6px)}
  .card:hover{border-color:var(--line-gold);transform:translateY(-3px)}
  .card .ico{font-size:24px;margin-bottom:14px;color:var(--gold-bright)}
  .card h3{font-size:19px;font-weight:700;margin-bottom:8px}
  .card p{color:var(--muted);font-size:15px}
  .num{display:inline-flex;align-items:center;justify-content:center;width:40px;height:40px;
    border-radius:50%;border:1px solid var(--line-gold);color:var(--gold);
    font-family:var(--serif);font-size:18px;margin-bottom:16px}

  /* ---- QR ---- */
  .qr-row{display:flex;gap:26px;flex-wrap:wrap;justify-content:center}
  .qr-box{background:var(--panel);border:1px solid var(--line);border-radius:var(--radius);
    padding:24px;text-align:center;width:240px}
  .qr-tile{width:172px;height:172px;background:#fff;border-radius:14px;margin:0 auto 16px;
    padding:10px;box-shadow:0 12px 40px rgba(0,0,0,.45)}
  .qr-tile svg{width:100%;height:100%;display:block}
  .qr-box h3{font-size:16px;font-weight:700}
  .qr-box .lnk{color:var(--gold);font-size:12.5px;word-break:break-all;margin-top:6px;display:block}

  /* ---- Témoignages ---- */
  .quote{background:var(--panel);border:1px solid var(--line);border-radius:var(--radius);padding:28px}
  .quote .stars{color:var(--gold);letter-spacing:2px;font-size:14px;margin-bottom:12px}
  .quote p{font-size:15.5px;line-height:1.65}
  .quote .who{margin-top:16px;display:flex;align-items:center;gap:12px}
  .quote .av{width:40px;height:40px;border-radius:50%;background:linear-gradient(135deg,var(--gold),#9c7d34);
    color:#1c1606;display:flex;align-items:center;justify-content:center;font-weight:800}
  .quote .who b{font-size:14.5px}.quote .who span{color:var(--muted);font-size:12.5px;display:block}

  /* ---- Tarifs ---- */
  .price-row{display:grid;grid-template-columns:repeat(2,1fr);gap:20px;max-width:760px;margin:0 auto}
  @media(max-width:640px){.price-row{grid-template-columns:1fr}}
  .price{background:var(--panel);border:1px solid var(--line);border-radius:24px;
    padding:38px 30px;text-align:center;position:relative}
  .price.feature{border-color:var(--gold);
    background:linear-gradient(180deg,rgba(216,183,102,.10),var(--panel));
    box-shadow:0 24px 70px rgba(216,183,102,.14)}
  .ribbon{position:absolute;top:-14px;left:50%;transform:translateX(-50%);
    background:linear-gradient(135deg,var(--gold-bright),var(--gold));color:#1c1606;
    font-weight:800;font-size:11.5px;letter-spacing:1.5px;padding:6px 16px;border-radius:999px}
  .price .plan{font-size:15px;color:var(--muted);font-weight:600;letter-spacing:1px;text-transform:uppercase}
  .price .amt{font-family:var(--serif);font-size:52px;margin:14px 0 2px}
  .price .amt .cur{font-size:24px;color:var(--muted)}
  .price .per{color:var(--muted);font-size:14px;margin-bottom:8px}
  .price .note{color:var(--gold);font-size:13.5px;font-weight:700;margin-bottom:18px}
  .price ul{list-style:none;text-align:left;margin:18px 0 24px;font-size:14.5px;color:var(--muted)}
  .price li{padding:7px 0 7px 26px;position:relative}
  .price li::before{content:"✓";position:absolute;left:0;color:var(--gold);font-weight:800}

  /* ---- Carte MAC ---- */
  .mac-card{background:linear-gradient(180deg,var(--panel-2),var(--panel));
    border:1px solid var(--line);border-radius:24px;padding:42px;text-align:center;max-width:660px;margin:0 auto}
  .mac-input{display:flex;gap:12px;flex-wrap:wrap;justify-content:center;margin-top:24px}
  .mac-input input{flex:1;min-width:240px;background:rgba(0,0,0,.4);border:1px solid var(--line);
    color:#fff;padding:16px 18px;border-radius:14px;font-size:17px;letter-spacing:1px;
    text-align:center;font-family:ui-monospace,monospace}
  .mac-input input:focus{outline:none;border-color:var(--gold)}
  .hint{color:var(--muted);font-size:13px;margin-top:14px}

  /* ---- FAQ ---- */
  details{background:var(--panel);border:1px solid var(--line);border-radius:16px;padding:20px 24px;margin-bottom:12px}
  details[open]{border-color:var(--line-gold)}
  summary{cursor:pointer;font-weight:600;font-size:16.5px;list-style:none}
  summary::-webkit-details-marker{display:none}
  summary::after{content:"+";float:right;color:var(--gold);font-weight:800}
  details[open] summary::after{content:"–"}
  details p{color:var(--muted);margin-top:12px;font-size:14.5px}

  /* ---- Footer ---- */
  footer{border-top:1px solid var(--line);padding:54px 0 40px;color:var(--muted);font-size:13.5px;
    background:var(--bg-soft)}
  footer a{color:var(--muted)}footer a:hover{color:var(--text)}
  .disclaimer{background:rgba(0,0,0,.35);border:1px solid var(--line);border-radius:14px;
    padding:18px 22px;font-size:12.5px;line-height:1.65;margin-bottom:28px}
  .foot-links{display:flex;gap:24px;flex-wrap:wrap;margin-top:14px}
  .hairline{height:1px;background:linear-gradient(90deg,transparent,var(--line-gold),transparent);
    max-width:var(--maxw);margin:0 auto}
</style>
</head>
<body>

<!-- ⚙️ À PERSONNALISER : ce bloc CONFIG uniquement -->
<script>
  const CONFIG = {
    whatsapp: "447307410512",                    // sans "+" ni espaces
    appUrl:  "https://app.7themotion.com/install",
    tvUrl:   "https://app.7themotion.com/tv",
    privacyUrl: "https://app.7themotion.com/privacy",
    prices: {
      year: { amount: "5,90", per: "/ an" },
      life: { amount: "9,90", per: "à vie, une seule fois" }
    },
    currency: "€"
  };
</script>

<!-- NAV -->
<header class="nav"><div class="wrap nav-in">
  <div class="logo">7&nbsp;<b>MOTION</b></div>
  <nav class="nav-links">
    <a href="#how">Comment ça marche</a>
    <a href="#download">Télécharger</a>
    <a href="#pricing">Tarifs</a>
    <a href="#activate">Activer</a>
    <a href="#trust">Confiance</a>
  </nav>
  <a class="btn btn-gold btn-nav" id="navWa">Accès VIP</a>
</div></header>

<!-- HERO -->
<section class="hero"><div class="wrap">
  <span class="eyebrow">Expérience premium</span>
  <h1>La télévision,<br><span class="accent">enfin sereine.</span></h1>
  <p class="lead">Installez-vous. Une image nette, fluide, sans coupure — sur votre téléphone
    comme sur votre TV. On s'occupe de tout, vous n'avez plus qu'à regarder.</p>
  <div class="hero-cta">
    <a class="btn btn-gold" id="dlPhone">Télécharger l'application</a>
    <a class="btn btn-ghost" id="waHero">Parler à un conseiller</a>
  </div>
  <div class="reassure">
    <span><i class="dot"></i> Activation en quelques minutes</span>
    <span><i class="dot"></i> Accompagnement humain</span>
    <span><i class="dot"></i> Sans engagement</span>
  </div>
</div></section>

<!-- BANDE CONFIANCE -->
<section class="trust" style="padding:40px 0"><div class="wrap">
  <div class="grid">
    <div class="item"><div class="tk">⚡</div><h3>Activation rapide</h3><p>Prêt en quelques minutes, sans technique.</p></div>
    <div class="item"><div class="tk">🤝</div><h3>Un humain vous répond</h3><p>Accompagnement réel, à chaque étape.</p></div>
    <div class="item"><div class="tk">🔒</div><h3>Discret &amp; sécurisé</h3><p>Vos informations restent privées.</p></div>
    <div class="item"><div class="tk">♾️</div><h3>Sur tous vos écrans</h3><p>Téléphone, TV, box — partout, ensemble.</p></div>
  </div>
</div></section>

<!-- COMMENT ÇA MARCHE -->
<section id="how"><div class="wrap">
  <div class="center" style="margin-bottom:48px">
    <span class="eyebrow">Simple, du début à la fin</span>
    <h2>Trois étapes, <span class="g">tout en douceur</span></h2>
  </div>
  <div class="grid g3">
    <div class="card"><div class="num">1</div><h3>Installez l'application</h3><p>Sur votre téléphone ou votre TV. Aucun compte, aucune complication.</p></div>
    <div class="card"><div class="num">2</div><h3>Partagez votre adresse</h3><p>L'app affiche une adresse unique. Envoyez-la-nous, on s'occupe du reste.</p></div>
    <div class="card"><div class="num">3</div><h3>Détendez-vous</h3><p>Tout s'active automatiquement. Vous n'avez plus qu'à profiter, sereinement.</p></div>
  </div>
</div></section>

<!-- TÉLÉCHARGEMENT -->
<section id="download" style="background:var(--bg-soft)"><div class="wrap">
  <div class="center" style="margin-bottom:44px">
    <span class="eyebrow">À portée de scan</span>
    <h2>Installez en <span class="g">un instant</span></h2>
  </div>
  <div class="qr-row">
    <div class="qr-box"><div class="qr-tile"><svg width="165" height="165" class="segno"><g transform="scale(5)"><path fill="#fff" d="M0 0h33v33h-33z"/><path class="qrline" stroke="#000" d="M2 2.5h7m2 0h1m1 0h5m2 0h1m1 0h1m1 0h7m-29 1h1m5 0h1m1 0h2m1 0h1m3 0h1m1 0h1m4 0h1m5 0h1m-29 1h1m1 0h3m1 0h1m1 0h3m3 0h1m1 0h1m1 0h3m1 0h1m1 0h3m1 0h1m-29 1h1m1 0h3m1 0h1m1 0h3m3 0h4m1 0h2m1 0h1m1 0h3m1 0h1m-29 1h1m1 0h3m1 0h1m5 0h4m2 0h3m1 0h1m1 0h3m1 0h1m-29 1h1m5 0h1m2 0h2m2 0h2m2 0h2m1 0h1m1 0h1m5 0h1m-29 1h7m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h7m-21 1h1m1 0h4m5 0h2m-21 1h1m5 0h1m1 0h1m1 0h2m2 0h2m1 0h1m1 0h1m1 0h2m2 0h3m-28 1h3m1 0h2m3 0h1m4 0h1m1 0h4m1 0h1m2 0h1m1 0h2m-28 1h2m1 0h1m1 0h4m2 0h1m3 0h1m1 0h1m2 0h1m-21 1h1m1 0h1m6 0h4m1 0h1m1 0h1m4 0h3m1 0h1m-26 1h2m3 0h4m4 0h2m1 0h1m3 0h1m1 0h2m4 0h1m-28 1h2m1 0h2m1 0h1m4 0h11m1 0h1m2 0h2m-29 1h1m2 0h2m1 0h5m1 0h4m8 0h3m-26 1h3m1 0h1m2 0h1m4 0h2m7 0h1m1 0h1m1 0h1m1 0h1m-29 1h2m3 0h2m1 0h1m2 0h2m1 0h1m2 0h2m1 0h1m2 0h1m1 0h2m-27 1h1m1 0h1m5 0h2m5 0h6m1 0h3m1 0h3m-29 1h2m2 0h3m2 0h1m2 0h4m3 0h1m1 0h1m1 0h3m2 0h1m-29 1h1m1 0h1m1 0h1m3 0h2m4 0h1m4 0h2m3 0h1m-25 1h1m1 0h2m2 0h2m2 0h3m2 0h1m1 0h1m1 0h6m1 0h3m-21 1h1m2 0h1m1 0h1m1 0h1m1 0h2m1 0h1m3 0h2m-26 1h7m2 0h2m1 0h4m2 0h3m1 0h1m1 0h3m-27 1h1m5 0h1m3 0h1m1 0h2m2 0h1m2 0h2m3 0h1m3 0h1m-29 1h1m1 0h3m1 0h1m3 0h1m2 0h1m1 0h1m3 0h7m1 0h2m-29 1h1m1 0h3m1 0h1m3 0h1m2 0h1m1 0h5m1 0h1m1 0h1m1 0h2m1 0h1m-29 1h1m1 0h3m1 0h1m3 0h4m1 0h3m1 0h9m-28 1h1m5 0h1m2 0h1m2 0h1m2 0h2m1 0h1m2 0h6m1 0h1m-29 1h7m1 0h2m1 0h2m2 0h3m1 0h1m4 0h1m1 0h1"/></g></svg></div><h3>Téléphone</h3><a class="lnk" id="lnkPhone"></a></div>
    <div class="qr-box"><div class="qr-tile"><svg width="165" height="165" class="segno"><g transform="scale(5)"><path fill="#fff" d="M0 0h33v33h-33z"/><path class="qrline" stroke="#000" d="M2 2.5h7m3 0h1m5 0h1m2 0h2m1 0h7m-29 1h1m5 0h1m1 0h5m1 0h1m2 0h1m4 0h1m5 0h1m-29 1h1m1 0h3m1 0h1m1 0h2m1 0h2m1 0h3m3 0h1m1 0h1m1 0h3m1 0h1m-29 1h1m1 0h3m1 0h1m3 0h3m4 0h4m1 0h1m1 0h3m1 0h1m-29 1h1m1 0h3m1 0h1m3 0h2m2 0h1m2 0h1m1 0h1m2 0h1m1 0h3m1 0h1m-29 1h1m5 0h1m2 0h1m4 0h1m3 0h2m2 0h1m5 0h1m-29 1h7m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h7m-18 1h1m2 0h2m1 0h1m2 0h1m-20 1h3m1 0h2m4 0h3m1 0h5m6 0h2m-28 1h1m4 0h1m2 0h1m3 0h1m1 0h2m1 0h1m1 0h1m1 0h2m1 0h3m1 0h1m-29 1h2m1 0h6m1 0h2m4 0h1m1 0h1m3 0h4m1 0h1m-26 1h1m2 0h1m3 0h1m2 0h3m4 0h2m2 0h2m3 0h1m-29 1h3m2 0h2m2 0h1m1 0h1m5 0h5m1 0h1m1 0h4m-28 1h2m2 0h1m4 0h1m1 0h1m2 0h1m1 0h3m2 0h2m1 0h2m1 0h1m-29 1h1m2 0h1m1 0h3m2 0h1m1 0h1m1 0h8m1 0h3m1 0h2m-24 1h1m1 0h1m3 0h2m1 0h1m3 0h1m2 0h2m1 0h2m-25 1h6m2 0h1m1 0h2m3 0h2m2 0h2m1 0h3m1 0h2m-25 1h1m2 0h1m2 0h1m1 0h2m2 0h1m3 0h1m2 0h1m-24 1h1m1 0h1m3 0h1m1 0h1m1 0h1m2 0h5m2 0h1m1 0h2m-22 1h4m1 0h1m1 0h1m1 0h4m2 0h3m1 0h2m1 0h4m-27 1h2m1 0h1m1 0h1m2 0h2m3 0h1m1 0h3m1 0h8m-20 1h1m3 0h1m3 0h1m3 0h1m3 0h2m1 0h2m-29 1h7m6 0h1m3 0h1m1 0h2m1 0h1m1 0h1m1 0h2m-28 1h1m5 0h1m1 0h3m1 0h1m3 0h1m3 0h1m3 0h1m2 0h2m-29 1h1m1 0h3m1 0h1m3 0h1m1 0h3m3 0h1m1 0h7m-27 1h1m1 0h3m1 0h1m1 0h1m1 0h2m1 0h1m2 0h2m1 0h1m4 0h1m2 0h1m-28 1h1m1 0h3m1 0h1m1 0h1m6 0h2m1 0h1m1 0h1m2 0h1m4 0h1m-29 1h1m5 0h1m1 0h2m3 0h2m1 0h1m1 0h1m1 0h2m2 0h2m1 0h1m-28 1h7m3 0h2m1 0h3m2 0h6m3 0h1"/></g></svg></div><h3>TV &amp; Box</h3><a class="lnk" id="lnkTv"></a></div>
  </div>
  <p class="center lead" style="margin:26px auto 0;font-size:14px">Scannez, installez, regardez. Lien direct, sans publicité ni inscription.</p>
</div></section>

<!-- POURQUOI CONFIANCE -->
<section id="trust"><div class="wrap">
  <div class="center" style="margin-bottom:48px">
    <span class="eyebrow">Une relation de confiance</span>
    <h2>Pourquoi des milliers de foyers <span class="g">nous restent fidèles</span></h2>
    <p class="lead center" style="margin-top:14px">Pas de promesses tape-à-l'œil. Une expérience qui tient,
      un accompagnement présent, et la tranquillité d'esprit avant tout.</p>
  </div>
  <div class="grid g3">
    <div class="card"><div class="ico">✦</div><h3>Une image qui ne lâche pas</h3><p>Démarrage rapide, anti-coupure, reconnexion automatique. Même quand le réseau faiblit, l'image tient.</p></div>
    <div class="card"><div class="ico">✦</div><h3>Toujours quelqu'un au bout</h3><p>Un vrai conseiller vous répond et reste avec vous jusqu'à ce que tout fonctionne. Pas de robot.</p></div>
    <div class="card"><div class="ico">✦</div><h3>Aucune mauvaise surprise</h3><p>Des tarifs clairs, rien de caché. Vous gardez le contrôle, du premier jour au dernier.</p></div>
  </div>

  <div class="grid g3" style="margin-top:22px">
    <div class="quote"><div class="stars">★★★★★</div><p>« Installé en cinq minutes, et depuis ça tourne sans accroc. On sent que c'est sérieux. »</p>
      <div class="who"><div class="av">K</div><div><b>Karim</b><span>Lyon, France</span></div></div></div>
    <div class="quote"><div class="stars">★★★★★</div><p>« Ce que j'ai aimé : on m'a accompagné jusqu'au bout. Aucune question laissée sans réponse. »</p>
      <div class="who"><div class="av">S</div><div><b>Sofia</b><span>Bruxelles, Belgique</span></div></div></div>
    <div class="quote"><div class="stars">★★★★★</div><p>« Fluide sur la TV comme sur le téléphone. Discret, propre, premium. Exactement ce que je cherchais. »</p>
      <div class="who"><div class="av">A</div><div><b>Adam</b><span>Montréal, Canada</span></div></div></div>
  </div>
</div></section>

<!-- TARIFS -->
<section id="pricing" style="background:var(--bg-soft)"><div class="wrap">
  <div class="center" style="margin-bottom:50px">
    <span class="eyebrow">Tarifs justes, sans piège</span>
    <h2>Deux choix, <span class="g">c'est tout</span></h2>
    <p class="lead center" style="margin-top:14px">Pas de catalogue interminable. Le juste prix, en toute transparence.</p>
  </div>
  <div class="price-row">
    <div class="price">
      <div class="plan">1 an</div>
      <div class="amt" id="pYear">—</div>
      <div class="per">pour découvrir en toute tranquillité</div>
      <ul><li>Activation complète</li><li>Accompagnement humain</li><li>Mises à jour incluses</li><li>Sans engagement</li></ul>
      <a class="btn btn-ghost" data-plan="1 an" style="width:100%">Choisir</a>
    </div>
    <div class="price feature">
      <div class="ribbon">★ LE PLUS SEREIN</div>
      <div class="plan">À vie</div>
      <div class="amt" id="pLife">—</div>
      <div class="note">Une seule fois. Pour toujours.</div>
      <ul><li>Tout, sans limite de durée</li><li>Accompagnement prioritaire</li><li>Mises à jour à vie</li><li>Le meilleur choix, l'esprit léger</li></ul>
      <a class="btn btn-gold" data-plan="à vie" style="width:100%">Choisir à vie</a>
    </div>
  </div>
  <p class="center hint" style="margin-top:22px">Le règlement se fait avec un conseiller, simplement, sur WhatsApp. Humain, rapide, rassurant.</p>
</div></section>

<!-- ACTIVER -->
<section id="activate"><div class="wrap">
  <div class="mac-card">
    <span class="eyebrow">Déjà l'application&nbsp;?</span>
    <h2 style="font-size:clamp(24px,3.6vw,32px)">Activez votre appareil</h2>
    <p class="lead center" style="margin:12px auto 0">Entrez l'adresse affichée dans l'app. On l'active, et tout arrive automatiquement.</p>
    <div class="mac-input">
      <input id="macInput" type="text" placeholder="MK : XX : XX : XX : XX : XX" maxlength="20" autocomplete="off" />
      <button class="btn btn-gold" id="macSend">Activer mon accès</button>
    </div>
    <p class="hint">Vous trouvez cette adresse sur l'écran d'accueil de l'app, ou dans « À propos ».</p>
  </div>
</div></section>

<!-- FAQ -->
<section style="background:var(--bg-soft)"><div class="wrap" style="max-width:780px">
  <div class="center" style="margin-bottom:40px">
    <span class="eyebrow">On vous répond franchement</span>
    <h2>Questions <span class="g">fréquentes</span></h2>
  </div>
  <details><summary>Est-ce compliqué à installer&nbsp;?</summary><p>Non. Vous installez l'app, vous nous envoyez votre adresse, et tout s'active. La plupart de nos clients sont prêts en quelques minutes — et si besoin, un conseiller reste avec vous.</p></details>
  <details><summary>Sur quels appareils ça fonctionne&nbsp;?</summary><p>Téléphones et tablettes Android, Android TV, Google TV, Amazon Fire Stick, NVIDIA SHIELD et la plupart des box Android. La version iPhone arrive.</p></details>
  <details><summary>Et si j'ai un souci&nbsp;?</summary><p>Un vrai conseiller vous répond sur WhatsApp et reste avec vous jusqu'à ce que tout fonctionne. Vous n'êtes jamais seul.</p></details>
  <details><summary>Comment se passe le paiement&nbsp;?</summary><p>Simplement, avec un conseiller, sur WhatsApp. Vous choisissez votre formule, on active votre appareil, c'est réglé en quelques minutes — sereinement.</p></details>
  <details><summary>L'image peut-elle couper&nbsp;?</summary><p>L'application est conçue pour la stabilité : démarrage rapide, anti-coupure et reconnexion automatique. Une bonne connexion (ou Ethernet sur la TV) garantit le meilleur confort.</p></details>
</div></section>

<!-- CTA FINAL -->
<section class="center"><div class="wrap">
  <span class="eyebrow">Prêt quand vous l'êtes</span>
  <h2>Offrez-vous la <span class="g">tranquillité</span></h2>
  <p class="lead center" style="margin:14px auto 30px">Installez l'application, dites-nous bonjour, et laissez-vous porter.</p>
  <div class="hero-cta">
    <a class="btn btn-gold" id="dlPhone2">Télécharger</a>
    <a class="btn btn-ghost" id="waBtn2">Nous écrire</a>
  </div>
</div></section>

<div class="hairline"></div>

<!-- FOOTER -->
<footer><div class="wrap">
  <div class="disclaimer"><b>Mention légale —</b> 7 MOTION est une application de lecture multimédia.
    Nous ne vendons, n'hébergeons et ne fournissons aucune chaîne ni aucun contenu : l'utilisateur
    apporte sa propre source et reste responsable de sa conformité dans son pays.</div>
  <div class="logo">7&nbsp;<b>MOTION</b></div>
  <p style="margin-top:8px">L'expérience télé, sereine et premium.</p>
  <div class="foot-links">
    <a href="#how">Comment ça marche</a>
    <a href="#pricing">Tarifs</a>
    <a href="#trust">Confiance</a>
    <a id="footPrivacy" href="#">Confidentialité</a>
    <a id="footWa" href="#">Nous contacter</a>
  </div>
  <p style="margin-top:18px;opacity:.6">© <span id="yr"></span> 7 MOTION. Tous droits réservés.</p>
</div></footer>

<script>
(function(){
  var C = window.CONFIG;
  var wa = function(msg){ return "https://wa.me/" + C.whatsapp + (msg ? "?text=" + encodeURIComponent(msg) : ""); };
  function set(id, attr, val){ var e=document.getElementById(id); if(e) e[attr]=val; }

  ["dlPhone","dlPhone2"].forEach(function(id){ set(id,"href",C.appUrl); });
  set("lnkPhone","href",C.appUrl); set("lnkPhone","textContent",C.appUrl.replace("https://",""));
  set("lnkTv","href",C.tvUrl);     set("lnkTv","textContent",C.tvUrl.replace("https://",""));
  set("footPrivacy","href",C.privacyUrl);

  var waGeneral = wa("Bonjour 👋 Je souhaite des renseignements sur 7 MOTION.");
  ["navWa","waHero","waBtn2","footWa"].forEach(function(id){ set(id,"href",waGeneral); });

  function price(id,p){ var e=document.getElementById(id);
    if(e&&p) e.innerHTML = '<span class="cur"></span>' + p.amount + ' ' + C.currency + ' <span class="cur" style="font-size:18px;display:block;margin-top:2px;color:var(--muted)">' + p.per + '</span>'; }
  price("pYear",C.prices.year); price("pLife",C.prices.life);

  document.querySelectorAll("[data-plan]").forEach(function(b){
    b.href = wa("Bonjour 👋 Je souhaite la formule " + b.getAttribute("data-plan") + " pour 7 MOTION.");
  });

  var send = document.getElementById("macSend");
  if(send){ send.addEventListener("click", function(){
    var mac = (document.getElementById("macInput").value || "").trim().toUpperCase();
    var msg = mac ? "Bonjour 👋 Je souhaite activer mon appareil. Mon adresse : " + mac
                  : "Bonjour 👋 Je souhaite activer mon appareil 7 MOTION.";
    window.open(wa(msg), "_blank");
  }); }

  set("yr","textContent", String(new Date().getFullYear()));
})();
</script>
</body>
</html>
`;
}
