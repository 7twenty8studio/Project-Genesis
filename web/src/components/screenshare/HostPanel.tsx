"use client";

import QRCode from "qrcode";
import { useEffect, useMemo, useState } from "react";
import { translator, type Lang } from "@/lib/i18n";
import { cleanId, obsLink, randomCode, roster, shareLink, type ObsOptions, type Seen } from "@/lib/screenshare/protocol";
import { Watcher } from "@/lib/screenshare/viewer";
import { ObsView } from "./ObsView";

const ROOM_KEY = "vs_screen_room";

/**
 * For whoever sets up OBS: the room's share link (and QR) for devices, then
 * every device in the room with its own OBS link and a live preview.
 */
export function HostPanel({ lang, site: fallbackSite, initialRoom }: { lang: Lang; site: string; initialRoom: string | null }) {
  const t = translator(lang);
  // Links point at the address this page was opened from (a preview deploy, or the venue Mac), else the site's own.
  const site = typeof window === "undefined" ? fallbackSite : window.location.origin;
  const [room, setRoom] = useState<string | null>(null);
  const [draft, setDraft] = useState("");
  const [seen, setSeen] = useState<Map<string, Seen>>(new Map());
  const [status, setStatus] = useState("connecting");
  const [now, setNow] = useState(0);
  const [qr, setQr] = useState<string | null>(null);
  const [options, setOptions] = useState<ObsOptions>({ fit: "contain", background: "clear", audio: false });
  const [previews, setPreviews] = useState<Set<string>>(new Set());
  const [copied, setCopied] = useState<string | null>(null);
  const [fixedId, setFixedId] = useState("");

  useEffect(() => {
    let saved: string | null = null;
    try {
      saved = cleanId(localStorage.getItem(ROOM_KEY));
    } catch {}
    const code = initialRoom ?? saved ?? randomCode(10);
    // eslint-disable-next-line react-hooks/set-state-in-effect -- read once from the browser after it mounts
    setRoom(code);
    setDraft(code);
  }, [initialRoom]);

  useEffect(() => {
    if (!room) return;
    try {
      localStorage.setItem(ROOM_KEY, room);
    } catch {}
    const url = new URL(window.location.href);
    url.searchParams.set("room", room);
    window.history.replaceState(null, "", url);
    const watcher = new Watcher(room, (map, s) => {
      setSeen(map);
      setStatus(s);
      setNow(Date.now());
    });
    QRCode.toDataURL(shareLink(site, room), { errorCorrectionLevel: "M", margin: 2, width: 360 }).then(setQr).catch(() => setQr(null));
    return () => watcher.close();
  }, [room, site]);

  const devices = useMemo(() => roster(seen, now), [seen, now]);

  async function copy(text: string, key: string) {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(key);
      setTimeout(() => setCopied((c) => (c === key ? null : c)), 2000);
    } catch {}
  }

  function chooseRoom(value: string) {
    const code = cleanId(value);
    if (code) setRoom(code);
  }

  if (!room) return null;
  const share = shareLink(site, room);
  const pill = "inline-flex min-h-10 items-center rounded-full border border-border px-4 text-sm font-medium hover:bg-surface-2";

  return (
    <div className="space-y-8">
      <section className="grid gap-6 rounded-3xl border border-border bg-surface p-5 sm:grid-cols-[1fr_auto]">
        <div>
          <p className="text-sm font-medium text-muted">{t("Room")}</p>
          <form
            className="mt-1 flex flex-wrap gap-2"
            onSubmit={(e) => {
              e.preventDefault();
              chooseRoom(draft);
            }}
          >
            <input
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              aria-label={t("Room")}
              className="min-h-11 w-48 rounded-xl border border-border bg-background px-3 font-mono text-lg"
            />
            {draft !== room ? (
              <button type="submit" className={pill}>
                {t("Use this room")}
              </button>
            ) : null}
            <button type="button" className={pill} onClick={() => setRoom(randomCode(10))}>
              {t("New room")}
            </button>
          </form>
          <p className="mt-4 text-sm font-medium text-muted">{t("Devices open this link to share")}</p>
          <p className="mt-1 break-all font-mono text-sm">{share}</p>
          <button type="button" className={`${pill} mt-2`} onClick={() => copy(share, "share")}>
            {copied === "share" ? t("Copied") : t("Copy link")}
          </button>
          <p className="mt-4 flex items-center gap-2 text-sm" role="status">
            <span aria-hidden="true" className={`h-2.5 w-2.5 rounded-full ${status === "open" ? "bg-green-600" : "bg-amber-500"}`} />
            {status === "open" ? t("Listening for devices") : t("Connecting to the room…")}
          </p>
        </div>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        {qr ? <img src={qr} alt={t("QR code for the share link")} width={180} height={180} className="rounded-xl" /> : null}
      </section>

      <section>
        <h2 className="text-xl font-semibold">{t("OBS link options")}</h2>
        <div className="mt-3 flex flex-wrap gap-x-6 gap-y-2 text-sm">
          <label className="inline-flex items-center gap-2">
            <input type="checkbox" checked={options.fit === "cover"} onChange={(e) => setOptions({ ...options, fit: e.target.checked ? "cover" : "contain" })} />
            {t("Fill the frame (crops the edges)")}
          </label>
          <label className="inline-flex items-center gap-2">
            <input
              type="checkbox"
              checked={options.background === "black"}
              onChange={(e) => setOptions({ ...options, background: e.target.checked ? "black" : "clear" })}
            />
            {t("Black background")}
          </label>
          <label className="inline-flex items-center gap-2">
            <input type="checkbox" checked={!!options.audio} onChange={(e) => setOptions({ ...options, audio: e.target.checked })} />
            {t("Include sound")}
          </label>
        </div>
      </section>

      <section>
        <h2 className="text-xl font-semibold">{t("Devices")}</h2>
        {devices.length === 0 ? (
          <p className="mt-3 rounded-2xl border border-border bg-surface-2 p-4 text-sm">{t("No devices yet. Open the share link on a device.")}</p>
        ) : (
          <ul className="mt-3 space-y-3">
            {devices.map((d) => {
              const link = obsLink(site, room, d.device, options);
              const open = previews.has(d.device);
              return (
                <li key={d.device} className="rounded-2xl border border-border bg-surface p-4">
                  <div className="flex flex-wrap items-center gap-3">
                    <span aria-hidden="true" className={`h-3 w-3 rounded-full ${d.live ? "bg-red-600" : "bg-green-600"}`} />
                    <span className="font-mono text-lg font-semibold">{d.device}</span>
                    <span className="text-muted">{d.name}</span>
                    <span className="text-sm text-muted">
                      {d.live ? (d.kind === "camera" ? t("Sharing the camera") : t("Sharing the screen")) : t("Not sharing")}
                    </span>
                    <span className="ms-auto flex flex-wrap gap-2">
                      <button type="button" className={pill} onClick={() => copy(link, d.device)}>
                        {copied === d.device ? t("Copied") : t("Copy OBS link")}
                      </button>
                      <button
                        type="button"
                        className={pill}
                        aria-pressed={open}
                        onClick={() => {
                          const next = new Set(previews);
                          if (open) next.delete(d.device);
                          else next.add(d.device);
                          setPreviews(next);
                        }}
                      >
                        {open ? t("Hide preview") : t("Preview")}
                      </button>
                    </span>
                  </div>
                  <p className="mt-2 break-all font-mono text-xs text-muted">{link}</p>
                  {open ? (
                    <div className="relative mt-3 aspect-video overflow-hidden rounded-xl bg-black">
                      <ObsView room={room} device={d.device} fit="contain" background="black" audio={false} label embedded />
                    </div>
                  ) : null}
                </li>
              );
            })}
          </ul>
        )}
      </section>

      <section className="space-y-2 text-sm leading-relaxed text-muted">
        <h2 className="text-xl font-semibold text-foreground">{t("In OBS")}</h2>
        <p>{t("Add a Browser source, paste the device's OBS link, and set the size to 1920 × 1080. Turn on Control audio via OBS if you included sound.")}</p>
        <p>{t("To set up OBS before the devices arrive, give each device a fixed ID. Type one here (letters, numbers and dashes), open its share link on that device, and paste its OBS link into OBS.")}</p>
        <input
          value={fixedId}
          onChange={(e) => setFixedId(e.target.value)}
          placeholder="stage-laptop"
          aria-label={t("Fixed ID")}
          className="min-h-11 w-56 rounded-xl border border-border bg-background px-3 font-mono text-base text-foreground"
        />
        {cleanId(fixedId) ? (
          <div className="flex flex-wrap gap-2">
            <button type="button" className={pill} onClick={() => copy(shareLink(site, room, cleanId(fixedId)!), "fixed-share")}>
              {copied === "fixed-share" ? t("Copied") : t("Copy share link")}
            </button>
            <button type="button" className={pill} onClick={() => copy(obsLink(site, room, cleanId(fixedId)!, options), "fixed-obs")}>
              {copied === "fixed-obs" ? t("Copied") : t("Copy OBS link")}
            </button>
          </div>
        ) : null}
      </section>
    </div>
  );
}
