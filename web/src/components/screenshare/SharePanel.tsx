"use client";

import { useEffect, useRef, useState } from "react";
import { translator, type Lang } from "@/lib/i18n";
import { canShareScreen, cleanId, cleanName, obsLink, randomCode, type ShareKind } from "@/lib/screenshare/protocol";
import { Sender } from "@/lib/screenshare/sender";

const DEVICE_KEY = "vs_screen_device";
const NAME_KEY = "vs_screen_name";

const stored = (key: string) => {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
};
const store = (key: string, value: string) => {
  try {
    localStorage.setItem(key, value);
  } catch {
    // Private browsing: the id just won't be remembered.
  }
};

/** A first name for the device, from what the browser says it is. */
function guessName(): string {
  const ua = navigator.userAgent;
  if (/iPhone/.test(ua)) return "iPhone";
  if (/iPad/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)) return "iPad";
  if (/Android/.test(ua)) return "Android";
  if (/Macintosh/.test(ua)) return "Mac";
  if (/Windows/.test(ua)) return "PC";
  return "Device";
}

/**
 * The page a device opens to go on the big screen: it gets its own id (kept on
 * the device, or fixed by ?device= for a ready-made OBS source), then shares
 * its screen, or its camera where the browser can't share the screen (iPhone,
 * iPad).
 */
export function SharePanel({ lang, room, presetDevice, site }: { lang: Lang; room: string; presetDevice: string | null; site: string }) {
  const t = translator(lang);
  const [device, setDevice] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [screenOK, setScreenOK] = useState(true);
  const [kind, setKind] = useState<ShareKind | null>(null);
  const [status, setStatus] = useState<"connecting" | "open" | "closed">("connecting");
  const [viewers, setViewers] = useState(0);
  const [problem, setProblem] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const sender = useRef<Sender | null>(null);
  const preview = useRef<HTMLVideoElement>(null);
  const wakeLock = useRef<{ release: () => Promise<void> } | null>(null);

  // The device's id and name, kept on this device.
  useEffect(() => {
    const id = presetDevice ?? cleanId(stored(DEVICE_KEY)) ?? randomCode(4);
    if (!presetDevice) store(DEVICE_KEY, id);
    // eslint-disable-next-line react-hooks/set-state-in-effect -- read once from the browser after it mounts
    setDevice(id);
    setName(cleanName(stored(NAME_KEY)) || guessName());
    setScreenOK(canShareScreen(navigator));
  }, [presetDevice]);

  useEffect(() => {
    if (!device) return;
    const s = new Sender(room, device, cleanName(stored(NAME_KEY)) || guessName(), ({ status, viewers }) => {
      setStatus(status);
      setViewers(viewers);
    });
    sender.current = s;
    const leave = () => s.close();
    window.addEventListener("pagehide", leave);
    return () => {
      window.removeEventListener("pagehide", leave);
      s.close();
      sender.current = null;
    };
  }, [room, device]);

  function rename(value: string) {
    setName(value);
    const clean = cleanName(value);
    store(NAME_KEY, clean);
    sender.current?.rename(clean);
  }

  async function start(what: ShareKind, facing: "user" | "environment" = "environment") {
    setProblem(null);
    let stream: MediaStream;
    try {
      stream = what === "screen" ? await screen() : await camera(facing);
    } catch (error) {
      const name = (error as Error)?.name;
      setProblem(
        name === "NotAllowedError"
          ? t("Sharing was stopped or not allowed. Try again, and allow it when the browser asks.")
          : t("This browser couldn't start sharing. Try Chrome, Edge or Safari on a computer."),
      );
      return;
    }
    sender.current?.share(stream, what);
    setKind(what);
    if (preview.current) preview.current.srcObject = stream;
    stream.getVideoTracks()[0]?.addEventListener("ended", () => {
      if (sender.current && !sender.current.live) stopped();
    });
    // Keep a phone's screen awake while its camera is on the big screen.
    try {
      wakeLock.current = await (navigator as Navigator & { wakeLock?: { request: (type: "screen") => Promise<{ release: () => Promise<void> }> } }).wakeLock?.request("screen") ?? null;
    } catch {
      wakeLock.current = null;
    }
  }

  function stopped() {
    setKind(null);
    if (preview.current) preview.current.srcObject = null;
    void wakeLock.current?.release().catch(() => {});
    wakeLock.current = null;
  }

  function stop() {
    sender.current?.stop();
    stopped();
  }

  async function copyObs() {
    if (!device) return;
    try {
      await navigator.clipboard.writeText(obsLink(site, room, device));
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      setCopied(false);
    }
  }

  const button = "inline-flex min-h-12 items-center justify-center rounded-full px-6 text-base font-semibold transition-opacity hover:opacity-90";

  return (
    <div className="space-y-6">
      <section className="rounded-3xl border border-border bg-surface p-5">
        <p className="text-sm font-medium text-muted">{t("This device's ID")}</p>
        <p className="mt-1 font-mono text-5xl font-semibold tracking-widest" aria-live="polite">
          {device ?? "····"}
        </p>
        <label className="mt-4 block text-sm font-medium text-muted" htmlFor="screen-name">
          {t("Name shown to the host")}
        </label>
        <input
          id="screen-name"
          value={name}
          maxLength={40}
          onChange={(e) => rename(e.target.value)}
          className="mt-1 min-h-11 w-full rounded-xl border border-border bg-background px-3 text-base"
        />
        <p className="mt-4 flex items-center gap-2 text-sm" role="status">
          <span
            aria-hidden="true"
            className={`h-2.5 w-2.5 rounded-full ${status === "open" ? (kind ? "bg-red-600" : "bg-green-600") : "bg-amber-500"}`}
          />
          {status !== "open"
            ? t("Connecting to the room…")
            : kind
              ? viewers > 0
                ? t("Live: on screen now")
                : t("Sharing: waiting for OBS to show it")
              : t("Connected. Nothing shared yet.")}
        </p>
      </section>

      <section className="space-y-3">
        {kind ? (
          <button type="button" onClick={stop} className={`${button} w-full bg-red-700 text-white`}>
            {t("Stop sharing")}
          </button>
        ) : (
          <>
            {screenOK ? (
              <button type="button" onClick={() => start("screen")} className={`${button} w-full bg-accent-strong text-on-accent`}>
                {t("Share my screen")}
              </button>
            ) : (
              <p className="rounded-2xl border border-border bg-surface-2 p-4 text-sm leading-relaxed">
                {t("iPhone and iPad browsers can't share the screen. You can share the camera instead, or mirror the screen to the Mac with AirPlay.")}
              </p>
            )}
            <div className="grid grid-cols-2 gap-3">
              <button type="button" onClick={() => start("camera", "environment")} className={`${button} border border-border bg-surface`}>
                {t("Back camera")}
              </button>
              <button type="button" onClick={() => start("camera", "user")} className={`${button} border border-border bg-surface`}>
                {t("Front camera")}
              </button>
            </div>
          </>
        )}
        {problem ? (
          <p role="alert" className="rounded-2xl border border-border bg-surface-2 p-4 text-sm">
            {problem}
          </p>
        ) : null}
      </section>

      <video ref={preview} autoPlay muted playsInline className={`w-full rounded-2xl bg-black ${kind ? "" : "hidden"}`} />

      <section className="text-sm leading-relaxed text-muted">
        <p>{t("The picture goes straight to the computer running OBS over this network. Nothing is recorded or saved.")}</p>
        <button type="button" onClick={copyObs} className="mt-2 font-medium text-accent underline-offset-4 hover:underline">
          {copied ? t("Copied") : t("Copy this device's OBS link")}
        </button>
      </section>
    </div>
  );
}

async function screen(): Promise<MediaStream> {
  const video = { frameRate: { ideal: 60, max: 60 }, width: { max: 3840 }, height: { max: 2160 } };
  const extras = { selfBrowserSurface: "exclude", surfaceSwitching: "include", systemAudio: "include" };
  try {
    return await navigator.mediaDevices.getDisplayMedia({ video, audio: true, ...extras } as DisplayMediaStreamOptions);
  } catch (error) {
    // Safari and some others refuse audio: try once more with the picture only.
    if ((error as Error)?.name === "NotAllowedError") throw error;
    return navigator.mediaDevices.getDisplayMedia({ video } as DisplayMediaStreamOptions);
  }
}

function camera(facing: "user" | "environment"): Promise<MediaStream> {
  return navigator.mediaDevices.getUserMedia({
    video: { facingMode: { ideal: facing }, width: { ideal: 1920 }, height: { ideal: 1080 }, frameRate: { ideal: 30 } },
    audio: false,
  });
}
