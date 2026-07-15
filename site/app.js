// Feature data — SEVEN branding, plain product descriptions.
// Icons are Material Design icons (Apache 2.0, open source).
const FEATURES = [
  {t:"Multiple playlists", d:"Organise and hop between all your playlists without any hassle", i:'<path d="M3 10h11v2H3zm0-4h11v2H3zm0 8h7v2H3zm13-1v8l6-4z"/>'},
  {t:"Favorite channels", d:"Pin the channels you watch most for one-tap access", i:'<path d="M12 17.27 18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z"/>'},
  {t:"Search", d:"Track down any channel or show in seconds with quick search", i:'<path d="M15.5 14h-.79l-.28-.27C15.41 12.59 16 11.11 16 9.5 16 5.91 13.09 3 9.5 3S3 5.91 3 9.5 5.91 16 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14"/>'},
  {t:"Multiview", d:"Keep several channels running at once on a single display", i:'<path fill-rule="evenodd" d="M3 3v8h8V3zm6 6H5V5h4zm-6 4v8h8v-8zm6 6H5v-4h4zm4-16v8h8V3zm6 6h-4V5h4zm-6 4v8h8v-8zm6 6h-4v-4h4z"/>'},
  {t:"Catch-up", d:"Rewind time and watch programmes that already aired", i:'<path d="M13 3c-4.97 0-9 4.03-9 9H1l3.89 3.89.07.14L9 12H6c0-3.87 3.13-7 7-7s7 3.13 7 7-3.13 7-7 7c-1.93 0-3.68-.79-4.94-2.06l-1.42 1.42C8.27 19.99 10.51 21 13 21c4.97 0 9-4.03 9-9s-4.03-9-9-9m-1 5v5l4.28 2.54.72-1.21-3.5-2.08V8z"/>'},
  {t:"Recording", d:"Capture the shows you love and play them back whenever", i:'<path d="M17 10.5V7c0-.55-.45-1-1-1H4c-.55 0-1 .45-1 1v10c0 .55.45 1 1 1h12c.55 0 1-.45 1-1v-3.5l4 4v-11z"/>'},
  {t:"Parental controls", d:"Set boundaries effortlessly to keep viewing safe for everyone", i:'<path d="M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2m-6 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2m3.1-9H8.9V6c0-1.71 1.39-3.1 3.1-3.1s3.1 1.39 3.1 3.1z"/>'},
  {t:"Personalization", d:"Shape the interface and layout to match how you like it", i:'<path d="M3 17v2h6v-2zM3 5v2h10V5zm10 16v-2h8v-2h-8v-2h-2v6zM7 9v2H3v2h4v2h2V9zm14 4v-2H11v2zm-6-4h2V7h4V5h-4V3h-2z"/>'}
];
const grid = document.getElementById('features');
grid.innerHTML = FEATURES.map(f=>`
  <div class="feature">
    <div class="icon-box"><svg viewBox="0 0 24 24" aria-hidden="true">${f.i}</svg></div>
    <div><h3>${f.t}</h3><p>${f.d}</p></div>
  </div>`).join('');

// Carousel scroll
const track = document.getElementById('track');
const step = () => Math.min(track.clientWidth, 912) + 16;
document.querySelector('.carousel-arrow.next').onclick = () => track.scrollBy({left:step(),behavior:'smooth'});
document.querySelector('.carousel-arrow.prev').onclick = () => track.scrollBy({left:-step(),behavior:'smooth'});
