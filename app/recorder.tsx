"use client";

import {
  useCallback,
  useEffect,
  useRef,
  useState,
  useSyncExternalStore,
} from "react";

const MAX_DURATION_SECONDS = 6 * 60 * 60;
const CHUNK_INTERVAL_MS = 5000;

type Status = "idle" | "ready" | "recording" | "paused" | "stopped";

function formatDuration(totalSeconds: number): string {
  const h = Math.floor(totalSeconds / 3600);
  const m = Math.floor((totalSeconds % 3600) / 60);
  const s = totalSeconds % 60;
  return [h, m, s].map((n) => n.toString().padStart(2, "0")).join(":");
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

function pickMimeType(): string {
  const candidates = [
    "video/webm;codecs=vp9,opus",
    "video/webm;codecs=vp8,opus",
    "video/webm",
    "video/mp4",
  ];
  for (const type of candidates) {
    if (typeof MediaRecorder !== "undefined" && MediaRecorder.isTypeSupported(type)) {
      return type;
    }
  }
  return "";
}

export default function Recorder() {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const previewRef = useRef<HTMLVideoElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const timerRef = useRef<number | null>(null);
  const startedAtRef = useRef<number>(0);
  const accumulatedRef = useRef<number>(0);

  const [status, setStatus] = useState<Status>("idle");
  const [elapsed, setElapsed] = useState(0);
  const [bytes, setBytes] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [downloadUrl, setDownloadUrl] = useState<string | null>(null);
  const [mimeType, setMimeType] = useState<string>("");
  const [pipActive, setPipActive] = useState(false);
  const [autoPip, setAutoPip] = useState(true);
  const pipSupported = useSyncExternalStore(
    () => () => {},
    () => !!document.pictureInPictureEnabled,
    () => false,
  );

  const stopTimer = useCallback(() => {
    if (timerRef.current !== null) {
      window.clearInterval(timerRef.current);
      timerRef.current = null;
    }
  }, []);

  const stopRecording = useCallback(() => {
    const recorder = recorderRef.current;
    if (recorder && recorder.state !== "inactive") {
      recorder.stop();
    }
    stopTimer();
  }, [stopTimer]);

  const startTimer = useCallback(() => {
    stopTimer();
    startedAtRef.current = Date.now();
    timerRef.current = window.setInterval(() => {
      const now = Date.now();
      const seconds =
        accumulatedRef.current + Math.floor((now - startedAtRef.current) / 1000);
      setElapsed(seconds);
      if (seconds >= MAX_DURATION_SECONDS) {
        stopRecording();
      }
    }, 250);
  }, [stopTimer, stopRecording]);

  const requestStream = useCallback(async () => {
    setError(null);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { width: { ideal: 1280 }, height: { ideal: 720 } },
        audio: { echoCancellation: true, noiseSuppression: true },
      });
      streamRef.current = stream;
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        videoRef.current.muted = true;
        await videoRef.current.play().catch(() => undefined);
      }
      setStatus("ready");
    } catch (err) {
      const message =
        err instanceof Error ? err.message : "Impossible d'accéder à la caméra.";
      setError(message);
    }
  }, []);

  const startRecording = useCallback(() => {
    const stream = streamRef.current;
    if (!stream) return;

    if (downloadUrl) {
      URL.revokeObjectURL(downloadUrl);
      setDownloadUrl(null);
    }
    chunksRef.current = [];
    setBytes(0);
    setElapsed(0);
    accumulatedRef.current = 0;

    const type = pickMimeType();
    setMimeType(type);

    let recorder: MediaRecorder;
    try {
      recorder = type
        ? new MediaRecorder(stream, {
            mimeType: type,
            videoBitsPerSecond: 1_200_000,
            audioBitsPerSecond: 128_000,
          })
        : new MediaRecorder(stream);
    } catch (err) {
      const message =
        err instanceof Error ? err.message : "MediaRecorder non supporté.";
      setError(message);
      return;
    }

    recorder.ondataavailable = (event) => {
      if (event.data && event.data.size > 0) {
        chunksRef.current.push(event.data);
        setBytes((prev) => prev + event.data.size);
      }
    };
    recorder.onerror = (event) => {
      const errEvent = event as unknown as { error?: { message?: string } };
      setError(errEvent.error?.message ?? "Erreur d'enregistrement.");
    };
    recorder.onstop = () => {
      stopTimer();
      const blob = new Blob(chunksRef.current, {
        type: type || "video/webm",
      });
      const url = URL.createObjectURL(blob);
      setDownloadUrl(url);
      if (previewRef.current) {
        previewRef.current.src = url;
      }
      setStatus("stopped");
    };

    recorder.start(CHUNK_INTERVAL_MS);
    recorderRef.current = recorder;
    setStatus("recording");
    startTimer();
  }, [downloadUrl, startTimer, stopTimer]);

  const pauseRecording = useCallback(() => {
    const recorder = recorderRef.current;
    if (!recorder || recorder.state !== "recording") return;
    recorder.pause();
    accumulatedRef.current += Math.floor(
      (Date.now() - startedAtRef.current) / 1000,
    );
    stopTimer();
    setStatus("paused");
  }, [stopTimer]);

  const resumeRecording = useCallback(() => {
    const recorder = recorderRef.current;
    if (!recorder || recorder.state !== "paused") return;
    recorder.resume();
    startTimer();
    setStatus("recording");
  }, [startTimer]);

  const releaseCamera = useCallback(() => {
    stopRecording();
    const stream = streamRef.current;
    if (stream) {
      stream.getTracks().forEach((track) => track.stop());
      streamRef.current = null;
    }
    if (videoRef.current) {
      videoRef.current.srcObject = null;
    }
    setStatus("idle");
    setElapsed(0);
  }, [stopRecording]);

  useEffect(() => {
    return () => {
      if (timerRef.current !== null) {
        window.clearInterval(timerRef.current);
      }
      const stream = streamRef.current;
      if (stream) stream.getTracks().forEach((track) => track.stop());
      if (downloadUrl) URL.revokeObjectURL(downloadUrl);
    };
  }, [downloadUrl]);

  useEffect(() => {
    const video = previewRef.current;
    if (!video) return;
    const onEnter = () => setPipActive(true);
    const onLeave = () => setPipActive(false);
    video.addEventListener("enterpictureinpicture", onEnter);
    video.addEventListener("leavepictureinpicture", onLeave);
    return () => {
      video.removeEventListener("enterpictureinpicture", onEnter);
      video.removeEventListener("leavepictureinpicture", onLeave);
    };
  }, [downloadUrl]);

  useEffect(() => {
    const video = previewRef.current;
    if (!video) return;
    type AutoPipVideo = HTMLVideoElement & { autoPictureInPicture?: boolean };
    (video as AutoPipVideo).autoPictureInPicture = autoPip;
    if (autoPip) {
      video.setAttribute("autopictureinpicture", "");
    } else {
      video.removeAttribute("autopictureinpicture");
    }
  }, [autoPip, downloadUrl]);

  useEffect(() => {
    if (!autoPip) return;
    const onVisibility = async () => {
      const video = previewRef.current;
      if (!video || video.paused || video.ended) return;
      if (document.visibilityState !== "hidden") return;
      if (document.pictureInPictureElement) return;
      try {
        await video.requestPictureInPicture();
      } catch {
        /* navigateur refuse sans geste utilisateur — silencieux */
      }
    };
    document.addEventListener("visibilitychange", onVisibility);
    return () => document.removeEventListener("visibilitychange", onVisibility);
  }, [autoPip]);

  const togglePip = useCallback(async () => {
    const video = previewRef.current;
    if (!video) return;
    try {
      if (document.pictureInPictureElement === video) {
        await document.exitPictureInPicture();
      } else {
        await video.requestPictureInPicture();
      }
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "Mini-lecteur indisponible.",
      );
    }
  }, []);

  const isRecording = status === "recording";
  const isPaused = status === "paused";
  const hasStream = status !== "idle";
  const progress = Math.min(1, elapsed / MAX_DURATION_SECONDS);

  const downloadName = `chambre-rouge-${new Date().toISOString().replace(/[:.]/g, "-")}.${
    mimeType.includes("mp4") ? "mp4" : "webm"
  }`;

  return (
    <div className="relative flex w-full max-w-5xl flex-col gap-6 rounded-3xl border border-red-900/40 bg-zinc-950/70 p-6 shadow-[0_0_60px_-15px_rgba(220,38,38,0.5)]">
      <div className="absolute -top-5 -right-5 z-10 flex h-20 w-20 rotate-12 items-center justify-center rounded-full border-4 border-red-600 bg-black text-red-500 shadow-lg shadow-red-600/40">
        <div className="flex flex-col items-center leading-none">
          <span className="text-[10px] font-semibold tracking-widest text-red-400">
            ADULT
          </span>
          <span className="text-2xl font-black">+18</span>
        </div>
      </div>

      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-3xl font-black tracking-tight text-zinc-100">
            Chambre <span className="text-red-500">Rouge</span>
          </h1>
          <p className="mt-1 text-sm text-zinc-400">
            Enregistre jusqu&apos;à{" "}
            <span className="font-semibold text-red-400">
              {Math.floor(MAX_DURATION_SECONDS / 3600)} heures
            </span>{" "}
            de vidéo (webcam + micro) directement dans le navigateur.
          </p>
        </div>
        <div className="flex items-center gap-2 rounded-full border border-zinc-800 bg-black/50 px-4 py-2 font-mono text-2xl tabular-nums text-zinc-100">
          {isRecording && (
            <span className="h-3 w-3 animate-pulse rounded-full bg-red-500 shadow-[0_0_10px_rgba(239,68,68,0.9)]" />
          )}
          <span>{formatDuration(elapsed)}</span>
          <span className="text-sm text-zinc-500">
            / {formatDuration(MAX_DURATION_SECONDS)}
          </span>
        </div>
      </header>

      <div className="h-1.5 w-full overflow-hidden rounded-full bg-zinc-900">
        <div
          className="h-full bg-gradient-to-r from-red-700 via-red-500 to-amber-400 transition-[width] duration-200"
          style={{ width: `${progress * 100}%` }}
        />
      </div>

      {error && (
        <div className="rounded-xl border border-red-700/60 bg-red-950/50 px-4 py-3 text-sm text-red-200">
          {error}
        </div>
      )}

      <div className="grid gap-4 md:grid-cols-2">
        <div className="relative overflow-hidden rounded-2xl border border-zinc-800 bg-black aspect-video">
          <video
            ref={videoRef}
            className="h-full w-full object-cover"
            playsInline
            autoPlay
            muted
          />
          {!hasStream && (
            <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 bg-zinc-950/80 text-zinc-400">
              <span className="text-5xl">📹</span>
              <p className="text-sm">Aucune caméra active</p>
            </div>
          )}
          {isRecording && (
            <div className="absolute top-3 left-3 flex items-center gap-2 rounded-full bg-red-600/90 px-3 py-1 text-xs font-bold uppercase tracking-wide text-white">
              <span className="h-2 w-2 animate-pulse rounded-full bg-white" />
              REC
            </div>
          )}
        </div>

        <div className="relative overflow-hidden rounded-2xl border border-zinc-800 bg-black aspect-video">
          <video
            ref={previewRef}
            className="h-full w-full object-cover"
            controls
            playsInline
          />
          {!downloadUrl && (
            <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 bg-zinc-950/80 text-zinc-400">
              <span className="text-5xl">🎬</span>
              <p className="text-sm">Aucun enregistrement disponible</p>
            </div>
          )}
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-3">
        {status === "idle" && (
          <button
            type="button"
            onClick={requestStream}
            className="rounded-full bg-red-600 px-6 py-3 text-sm font-bold uppercase tracking-wide text-white transition hover:bg-red-500"
          >
            Activer la caméra
          </button>
        )}

        {status === "ready" && (
          <button
            type="button"
            onClick={startRecording}
            className="rounded-full bg-red-600 px-6 py-3 text-sm font-bold uppercase tracking-wide text-white transition hover:bg-red-500"
          >
            ● Démarrer l&apos;enregistrement
          </button>
        )}

        {isRecording && (
          <>
            <button
              type="button"
              onClick={pauseRecording}
              className="rounded-full border border-zinc-700 bg-zinc-900 px-6 py-3 text-sm font-bold uppercase tracking-wide text-zinc-100 transition hover:bg-zinc-800"
            >
              ❚❚ Pause
            </button>
            <button
              type="button"
              onClick={stopRecording}
              className="rounded-full bg-zinc-100 px-6 py-3 text-sm font-bold uppercase tracking-wide text-black transition hover:bg-white"
            >
              ■ Stop
            </button>
          </>
        )}

        {isPaused && (
          <>
            <button
              type="button"
              onClick={resumeRecording}
              className="rounded-full bg-red-600 px-6 py-3 text-sm font-bold uppercase tracking-wide text-white transition hover:bg-red-500"
            >
              ▶ Reprendre
            </button>
            <button
              type="button"
              onClick={stopRecording}
              className="rounded-full bg-zinc-100 px-6 py-3 text-sm font-bold uppercase tracking-wide text-black transition hover:bg-white"
            >
              ■ Stop
            </button>
          </>
        )}

        {status === "stopped" && (
          <>
            <button
              type="button"
              onClick={startRecording}
              className="rounded-full bg-red-600 px-6 py-3 text-sm font-bold uppercase tracking-wide text-white transition hover:bg-red-500"
            >
              ● Nouveau clip
            </button>
            {downloadUrl && (
              <a
                href={downloadUrl}
                download={downloadName}
                className="rounded-full bg-emerald-500 px-6 py-3 text-sm font-bold uppercase tracking-wide text-black transition hover:bg-emerald-400"
              >
                ⬇ Télécharger
              </a>
            )}
            {pipSupported && downloadUrl && (
              <button
                type="button"
                onClick={togglePip}
                className="rounded-full border border-red-700 bg-red-950/40 px-6 py-3 text-sm font-bold uppercase tracking-wide text-red-200 transition hover:bg-red-900/40"
              >
                {pipActive ? "⊠ Fermer mini-lecteur" : "▭ Mini-lecteur"}
              </button>
            )}
          </>
        )}

        {hasStream && (
          <button
            type="button"
            onClick={releaseCamera}
            className="ml-auto rounded-full border border-zinc-800 px-4 py-2 text-xs uppercase tracking-wide text-zinc-400 transition hover:bg-zinc-900 hover:text-zinc-100"
          >
            Libérer la caméra
          </button>
        )}
      </div>

      <footer className="flex flex-wrap items-center justify-between gap-3 border-t border-zinc-900 pt-4 text-xs text-zinc-500">
        <span>
          Format :{" "}
          <span className="text-zinc-300">{mimeType || "auto (webm)"}</span>
        </span>
        <span>
          Taille : <span className="text-zinc-300">{formatBytes(bytes)}</span>
        </span>
        {pipSupported && (
          <label className="flex cursor-pointer items-center gap-2 text-zinc-400">
            <input
              type="checkbox"
              checked={autoPip}
              onChange={(e) => setAutoPip(e.target.checked)}
              className="h-3.5 w-3.5 accent-red-500"
            />
            Mini-lecteur auto quand je change d&apos;app
          </label>
        )}
        <span className="text-amber-400/80">
          ⚠ Les longs enregistrements consomment beaucoup de mémoire. Pour 6h, prévois
          plusieurs Go libres.
        </span>
      </footer>
    </div>
  );
}
