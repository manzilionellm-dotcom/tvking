/*
 * Polyfills pour les WebView anciens des box TV (Android 6/7/8 : Chrome 55–80).
 *
 * Next.js ne transpile la syntaxe que selon `browserslist` (package.json) et ne
 * fournit d'office que fetch/URL/Object.assign ; les MÉTHODES plus récentes
 * utilisées par l'app ou par React doivent être fournies ici. Chaque bloc est
 * gardé (`if (!…)`) : sur un navigateur moderne, rien n'est touché.
 *
 * Chargé avant tout le code applicatif via instrumentation-client.ts.
 */

/* eslint-disable @typescript-eslint/no-explicit-any */

type AnyFn = (...args: any[]) => any;

function define(obj: any, name: string, fn: AnyFn): void {
  try {
    Object.defineProperty(obj, name, {
      value: fn,
      writable: true,
      configurable: true,
      enumerable: false,
    });
  } catch {
    // Prototype figé (WebView exotique) : on laisse tel quel.
  }
}

(function installPolyfills() {
  if (typeof window === "undefined") return;
  const w = window as any;

  // globalThis — Chrome 71+
  if (typeof w.globalThis === "undefined") w.globalThis = w;

  // String.prototype.padStart / padEnd — Chrome 57+ (utilisé par l'horloge du
  // lecteur : sans lui, ouvrir une chaîne plantait sur les vieux box).
  const sp = String.prototype as any;
  if (!sp.padStart) {
    define(sp, "padStart", function (this: string, len: number, pad?: string) {
      const s = String(this);
      const fill = pad === undefined ? " " : String(pad);
      if (s.length >= len || fill === "") return s;
      let out = "";
      while (out.length < len - s.length) out += fill;
      return out.slice(0, len - s.length) + s;
    });
  }
  if (!sp.padEnd) {
    define(sp, "padEnd", function (this: string, len: number, pad?: string) {
      const s = String(this);
      const fill = pad === undefined ? " " : String(pad);
      if (s.length >= len || fill === "") return s;
      let out = s;
      while (out.length < len) out += fill;
      return out.slice(0, Math.max(len, s.length));
    });
  }
  if (!sp.trimStart) {
    define(sp, "trimStart", function (this: string) {
      return String(this).replace(/^\s+/, "");
    });
  }
  if (!sp.trimEnd) {
    define(sp, "trimEnd", function (this: string) {
      return String(this).replace(/\s+$/, "");
    });
  }
  if (!sp.replaceAll) {
    define(sp, "replaceAll", function (this: string, search: any, replace: any) {
      if (search instanceof RegExp) return String(this).replace(search, replace);
      return String(this).split(String(search)).join(String(replace));
    });
  }
  if (!sp.at) {
    define(sp, "at", function (this: string, i: number) {
      const s = String(this);
      const n = Math.trunc(i) || 0;
      const k = n < 0 ? s.length + n : n;
      return k >= 0 && k < s.length ? s[k] : undefined;
    });
  }

  // Array.prototype.flat / flatMap — Chrome 69+ (utilisé par le catalogue).
  const ap = Array.prototype as any;
  if (!ap.flat) {
    define(ap, "flat", function (this: any[], depth?: number) {
      const d = depth === undefined ? 1 : Math.floor(depth);
      const flatten = (arr: any[], dd: number): any[] => {
        const out: any[] = [];
        for (const v of arr) {
          if (Array.isArray(v) && dd > 0) out.push(...flatten(v, dd - 1));
          else out.push(v);
        }
        return out;
      };
      return flatten(this, d);
    });
  }
  if (!ap.flatMap) {
    define(ap, "flatMap", function (this: any[], cb: AnyFn, thisArg?: any) {
      return (this.map(cb, thisArg) as any).flat(1);
    });
  }
  if (!ap.includes) {
    define(ap, "includes", function (this: any[], v: any, from?: number) {
      return this.indexOf(v, from) !== -1 || (v !== v && this.some((x) => x !== x));
    });
  }
  if (!ap.at) {
    define(ap, "at", function (this: any[], i: number) {
      const n = Math.trunc(i) || 0;
      const k = n < 0 ? this.length + n : n;
      return k >= 0 && k < this.length ? this[k] : undefined;
    });
  }

  // Object.entries / values / fromEntries — Chrome 54/54/73+ (stores persistés).
  const O = Object as any;
  if (!O.entries) {
    O.entries = (obj: any) => Object.keys(obj).map((k) => [k, obj[k]]);
  }
  if (!O.values) {
    O.values = (obj: any) => Object.keys(obj).map((k) => obj[k]);
  }
  if (!O.fromEntries) {
    O.fromEntries = (iter: Iterable<[any, any]>) => {
      const out: any = {};
      for (const pair of Array.from(iter as any) as [any, any][]) out[pair[0]] = pair[1];
      return out;
    };
  }

  // Promise.prototype.finally — Chrome 63+ ; Promise.allSettled — Chrome 76+.
  const P = w.Promise;
  if (P && !P.prototype.finally) {
    define(P.prototype, "finally", function (this: Promise<any>, cb: AnyFn) {
      return this.then(
        (v) => P.resolve(cb()).then(() => v),
        (e) =>
          P.resolve(cb()).then(() => {
            throw e;
          })
      );
    });
  }
  if (P && !P.allSettled) {
    P.allSettled = (items: any[]) =>
      P.all(
        Array.from(items).map((p: any) =>
          P.resolve(p).then(
            (value: any) => ({ status: "fulfilled", value }),
            (reason: any) => ({ status: "rejected", reason })
          )
        )
      );
  }

  // queueMicrotask — Chrome 71+ (utilisé par React/Next).
  if (typeof w.queueMicrotask !== "function") {
    w.queueMicrotask = (cb: AnyFn) => {
      P.resolve().then(cb);
    };
  }

  // CSS.escape — sécurise la restauration du focus D-pad.
  if (typeof w.CSS === "undefined") w.CSS = {};
  if (typeof w.CSS.escape !== "function") {
    // Version simplifiée mais sûre : tout caractère hors [a-zA-Z0-9_-] est échappé.
    w.CSS.escape = (value: any) =>
      String(value).replace(/[^a-zA-Z0-9_-]/g, (ch) => "\\" + ch);
  }

  // AbortController minimal — Chrome 66+ (le fetch des vieux WebView l'ignore,
  // il suffit qu'instancier + abort() ne plantent pas).
  if (typeof w.AbortController === "undefined") {
    const listeners = new WeakMap<any, AnyFn[]>();
    function AbortSignalShim(this: any) {
      this.aborted = false;
      this.onabort = null;
      listeners.set(this, []);
    }
    AbortSignalShim.prototype.addEventListener = function (type: string, cb: AnyFn) {
      if (type === "abort") (listeners.get(this) || []).push(cb);
    };
    AbortSignalShim.prototype.removeEventListener = function (type: string, cb: AnyFn) {
      const arr = listeners.get(this) || [];
      const i = arr.indexOf(cb);
      if (i !== -1) arr.splice(i, 1);
    };
    AbortSignalShim.prototype.dispatchEvent = function () {
      return true;
    };
    function AbortControllerShim(this: any) {
      this.signal = new (AbortSignalShim as any)();
    }
    AbortControllerShim.prototype.abort = function () {
      if (this.signal.aborted) return;
      this.signal.aborted = true;
      const ev = { type: "abort", target: this.signal };
      if (typeof this.signal.onabort === "function") this.signal.onabort(ev);
      for (const cb of listeners.get(this.signal) || []) cb(ev);
    };
    w.AbortController = AbortControllerShim;
    w.AbortSignal = AbortSignalShim;
  }
})();

export {};
