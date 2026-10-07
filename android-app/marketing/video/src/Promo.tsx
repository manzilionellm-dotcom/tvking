import React from 'react';
import {
  AbsoluteFill, Img, Sequence, interpolate, spring, staticFile,
  useCurrentFrame, useVideoConfig, Easing,
} from 'remotion';

// Palette alignée sur AppColors (lib/core/theme/app_colors.dart)
const C = {
  bg: '#0A0A0C', surface: '#14141A', surfaceHigh: '#1C1C24',
  ember: '#E94B3C', emberBright: '#FF5A4A', cream: '#E8D9C0',
  text: '#F0EDE9', text2: '#B6B0A8', text3: '#7E7872',
};
const FONT = 'Inter, "Helvetica Neue", Arial, sans-serif';

export const FPS = 30;
const S = (sec: number) => Math.round(sec * FPS);
export const DURATION = S(20);

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

/** Apparition : fondu + glissement vers le haut, avec un ressort. */
const Rise: React.FC<{delay?: number; children: React.ReactNode; style?: React.CSSProperties}> = ({delay = 0, children, style}) => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const p = spring({frame: f - delay, fps, config: {damping: 16, stiffness: 120}});
  return <div style={{opacity: p, transform: `translateY(${(1 - p) * 70}px)`, ...style}}>{children}</div>;
};

/** Fondu de sortie sur les dernières frames d'une scène. */
const useFadeOut = (len: number, tail = 8) => {
  const f = useCurrentFrame();
  return interpolate(f, [len - tail, len], [1, 0], clamp);
};

const Glow: React.FC<{x: string; y: string; size: number; o?: number}> = ({x, y, size, o = 0.35}) => {
  const f = useCurrentFrame();
  const pulse = 1 + Math.sin(f / 22) * 0.06;
  return (
    <div style={{
      position: 'absolute', left: x, top: y, width: size, height: size, borderRadius: '50%',
      transform: `translate(-50%,-50%) scale(${pulse})`,
      background: `radial-gradient(circle, ${C.ember} 0%, transparent 65%)`, opacity: o, filter: 'blur(40px)',
    }} />
  );
};

const Backdrop: React.FC = () => (
  <AbsoluteFill style={{background: `radial-gradient(120% 80% at 50% 0%, #1a1115 0%, ${C.bg} 60%)`}} />
);

// ---------- Scène 1 : accroche ----------
const Hook: React.FC = () => {
  const o = useFadeOut(S(3));
  const f = useCurrentFrame();
  const words = ['Ta source.', 'Ton écran.', 'Zéro compromis.'];
  return (
    <AbsoluteFill style={{justifyContent: 'center', padding: '0 90px', opacity: o}}>
      <Glow x="80%" y="30%" size={900} />
      {words.map((w, i) => (
        <Rise key={w} delay={i * 18}>
          <div style={{
            fontFamily: FONT, fontWeight: 800, fontSize: i === 2 ? 128 : 140, lineHeight: 1.05,
            letterSpacing: -4, color: i === 2 ? C.emberBright : C.text, marginBottom: 20,
          }}>{w}</div>
        </Rise>
      ))}
      <div style={{
        marginTop: 40, height: 6, width: interpolate(f, [50, 80], [0, 420], {...clamp, easing: Easing.out(Easing.cubic)}),
        background: C.cream, borderRadius: 3,
      }} />
    </AbsoluteFill>
  );
};

// ---------- Scène 2 : logo ----------
const LogoReveal: React.FC = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const o = useFadeOut(S(3));
  const p = spring({frame: f, fps, config: {damping: 12, stiffness: 90}});
  const ring = interpolate(f, [0, 40], [0.6, 2.4], clamp);
  return (
    <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', opacity: o}}>
      <Glow x="50%" y="42%" size={1100} o={0.4} />
      <div style={{position: 'absolute', top: '42%', left: '50%', width: 420, height: 420, borderRadius: '50%',
        border: `4px solid ${C.ember}`, transform: `translate(-50%,-50%) scale(${ring})`,
        opacity: interpolate(f, [0, 40], [0.7, 0], clamp)}} />
      <Img src={staticFile('icon.png')} style={{width: 420, height: 420, borderRadius: 96,
        transform: `scale(${p})`, boxShadow: `0 40px 120px ${C.ember}55`, marginTop: -220}} />
      <Rise delay={14} style={{marginTop: 70, textAlign: 'center'}}>
        <div style={{fontFamily: FONT, fontWeight: 800, fontSize: 150, letterSpacing: 10, color: C.text}}>7 MOTION</div>
        <div style={{fontFamily: FONT, fontWeight: 500, fontSize: 48, color: C.cream, letterSpacing: 6, marginTop: 10}}>
          LE LECTEUR IPTV PREMIUM
        </div>
      </Rise>
    </AbsoluteFill>
  );
};

// ---------- Maquette téléphone (UI recréée, aucun contenu tiers) ----------
const CATS: Array<[string, string]> = [
  ['Sport', 'En direct'], ['Cinéma', 'HD / 4K'], ['Actualités', 'En continu'],
  ['Jeunesse', 'Famille'], ['Musique', 'Clips & radios'],
];

const Phone: React.FC<{scene: 'list' | 'player'; local: number}> = ({scene, local}) => {
  const {fps} = useVideoConfig();
  const pop = spring({frame: local, fps, config: {damping: 15, stiffness: 100}});
  return (
    <div style={{
      width: 640, height: 1120, borderRadius: 88, background: '#000', border: `10px solid #26262e`,
      boxShadow: `0 60px 160px ${C.ember}33, 0 0 0 2px #3a3a44`, overflow: 'hidden', position: 'relative',
      transform: `translateY(${(1 - pop) * 200}px) scale(${0.92 + pop * 0.08})`, opacity: pop, fontFamily: FONT,
    }}>
      <div style={{position: 'absolute', inset: 0, background: C.bg, padding: '56px 34px'}}>
        {scene === 'list' ? (
          <>
            <div style={{display: 'flex', alignItems: 'center', gap: 18}}>
              <Img src={staticFile('icon.png')} style={{width: 64, height: 64, borderRadius: 16}} />
              <div style={{fontSize: 40, fontWeight: 800, color: C.text}}>7 MOTION</div>
            </div>
            <div style={{fontSize: 30, fontWeight: 700, color: C.cream, margin: '44px 0 20px'}}>En direct</div>
            {CATS.map(([t, s], i) => {
              const p = spring({frame: local - 10 - i * 6, fps, config: {damping: 16}});
              return (
                <div key={t} style={{
                  background: C.surfaceHigh, borderRadius: 24, padding: '26px 28px', marginBottom: 18,
                  display: 'flex', alignItems: 'center', gap: 20, opacity: p, transform: `translateX(${(1 - p) * 80}px)`,
                }}>
                  <div style={{width: 60, height: 60, borderRadius: 16, background: C.surface, border: `2px solid ${C.ember}55`}} />
                  <div>
                    <div style={{fontSize: 32, fontWeight: 700, color: C.text}}>{t}</div>
                    <div style={{fontSize: 24, color: C.text3}}>{s}</div>
                  </div>
                </div>
              );
            })}
          </>
        ) : (
          <>
            <div style={{height: 380, marginTop: 70, background: 'linear-gradient(135deg,#1a1520,#0f0f14)', borderRadius: 24,
              position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center'}}>
              <div style={{position: 'absolute', top: 22, left: 22, background: C.ember, color: '#fff', fontWeight: 800,
                fontSize: 24, padding: '8px 18px', borderRadius: 12}}>● LIVE</div>
              <div style={{width: 120, height: 120, borderRadius: '50%', border: `5px solid ${C.text}`, display: 'flex',
                alignItems: 'center', justifyContent: 'center'}}>
                <div style={{borderLeft: `46px solid ${C.text}`, borderTop: '28px solid transparent',
                  borderBottom: '28px solid transparent', marginLeft: 12}} />
              </div>
            </div>
            <div style={{fontSize: 32, fontWeight: 700, color: C.text, marginTop: 36}}>En ce moment</div>
            <div style={{fontSize: 24, color: C.text3, marginTop: 6}}>Ensuite : à suivre</div>
            <div style={{height: 14, background: '#3a3a44', borderRadius: 7, marginTop: 26, overflow: 'hidden'}}>
              <div style={{height: '100%', width: `${interpolate(local, [0, 90], [30, 72], clamp)}%`, background: C.ember}} />
            </div>
            <div style={{display: 'flex', justifyContent: 'space-between', marginTop: 90}}>
              {['CC', '1x', '[ ]', 'REC', 'PiP'].map((l, i) => (
                <div key={l} style={{width: 92, height: 92, borderRadius: '50%', background: C.surfaceHigh,
                  display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 800, fontSize: 26,
                  color: l === 'REC' ? C.ember : C.text,
                  transform: `scale(${spring({frame: local - 20 - i * 5, fps, config: {damping: 12}})})`}}>{l}</div>
              ))}
            </div>
          </>
        )}
      </div>
    </div>
  );
};

const Caption: React.FC<{small: string; big: string}> = ({small, big}) => (
  <Rise style={{textAlign: 'center', padding: '0 70px'}}>
    <div style={{fontFamily: FONT, fontWeight: 600, fontSize: 40, color: C.cream, letterSpacing: 8, textTransform: 'uppercase'}}>{small}</div>
    <div style={{fontFamily: FONT, fontWeight: 800, fontSize: 96, color: C.text, letterSpacing: -2, lineHeight: 1.05, marginTop: 14}}>{big}</div>
  </Rise>
);

const PhoneScene: React.FC<{scene: 'list' | 'player'; small: string; big: string; len: number}> = ({scene, small, big, len}) => {
  const f = useCurrentFrame();
  const o = useFadeOut(len);
  return (
    <AbsoluteFill style={{alignItems: 'center', justifyContent: 'space-between', padding: '110px 0 70px', opacity: o}}>
      <Glow x="50%" y="62%" size={1000} o={0.3} />
      <Caption small={small} big={big} />
      <Phone scene={scene} local={f} />
    </AbsoluteFill>
  );
};

// ---------- Scène 5 : fonctionnalités ----------
const FEATURES = ['Guide des programmes', 'Replay / Catch-up', 'Enregistrement', 'Chromecast', 'Picture-in-Picture', 'Android TV · Fire TV'];

const Features: React.FC = () => {
  const o = useFadeOut(S(3.5));
  return (
    <AbsoluteFill style={{justifyContent: 'center', padding: '0 80px', opacity: o}}>
      <Glow x="20%" y="75%" size={900} o={0.3} />
      <Rise><div style={{fontFamily: FONT, fontWeight: 800, fontSize: 104, color: C.text, letterSpacing: -3, marginBottom: 60, lineHeight: 1.05}}>
        Tout ce qu’il faut. <span style={{color: C.emberBright}}>Rien de trop.</span></div></Rise>
      {FEATURES.map((t, i) => (
        <Rise key={t} delay={12 + i * 9}>
          <div style={{fontFamily: FONT, fontWeight: 600, fontSize: 54, color: C.text, background: C.surfaceHigh,
            borderRadius: 28, padding: '26px 36px', marginBottom: 22, display: 'flex', alignItems: 'center', gap: 26,
            borderLeft: `8px solid ${C.ember}`}}>
            <span style={{color: C.cream}}>✓</span>{t}
          </div>
        </Rise>
      ))}
    </AbsoluteFill>
  );
};

// ---------- Scène 6 : appel à l'action ----------
const CTA: React.FC = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const pulse = 1 + Math.sin(f / 7) * 0.025;
  const p = spring({frame: f - 8, fps, config: {damping: 10, stiffness: 110}});
  return (
    <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', textAlign: 'center', padding: '0 70px'}}>
      <Glow x="50%" y="45%" size={1200} o={0.4} />
      <Img src={staticFile('icon.png')} style={{width: 220, height: 220, borderRadius: 52, marginBottom: 50,
        transform: `scale(${spring({frame: f, fps})})`}} />
      <Rise delay={4}><div style={{fontFamily: FONT, fontWeight: 800, fontSize: 118, color: C.text, letterSpacing: -3, lineHeight: 1.05}}>
        7 jours d’essai <span style={{color: C.emberBright}}>gratuit</span></div></Rise>
      <div style={{marginTop: 70, transform: `scale(${p * pulse})`, background: C.ember, color: '#fff', fontFamily: FONT,
        fontWeight: 800, fontSize: 62, padding: '36px 80px', borderRadius: 100, boxShadow: `0 20px 80px ${C.ember}88`}}>
        Télécharger 7 MOTION</div>
      <Rise delay={30}><div style={{fontFamily: FONT, fontWeight: 500, fontSize: 36, color: C.text2, marginTop: 70, lineHeight: 1.4}}>
        Lecteur uniquement : ajoutez votre propre source M3U / Xtream.<br />Aucun contenu ni abonnement fourni.</div></Rise>
    </AbsoluteFill>
  );
};

export const Promo: React.FC = () => (
  <AbsoluteFill style={{background: C.bg}}>
    <Backdrop />
    <Sequence from={0} durationInFrames={S(3)}><Hook /></Sequence>
    <Sequence from={S(3)} durationInFrames={S(3)}><LogoReveal /></Sequence>
    <Sequence from={S(6)} durationInFrames={S(3.5)}>
      <PhoneScene scene="list" small="Interface premium" big="Tout est à portée de pouce" len={S(3.5)} />
    </Sequence>
    <Sequence from={S(9.5)} durationInFrames={S(3.5)}>
      <PhoneScene scene="player" small="Lecteur fluide" big="Live, replay, REC" len={S(3.5)} />
    </Sequence>
    <Sequence from={S(13)} durationInFrames={S(3.5)}><Features /></Sequence>
    <Sequence from={S(16.5)} durationInFrames={S(3.5)}><CTA /></Sequence>
  </AbsoluteFill>
);
