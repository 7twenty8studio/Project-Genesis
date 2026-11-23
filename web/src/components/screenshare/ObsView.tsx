"use client";

import { useEffect, useRef, useState } from "react";
import { Viewer } from "@/lib/screenshare/viewer";

/**
 * One device, full size, for an OBS browser source (1920 × 1080). Nothing else
 * on the page: a clear (or black) background until the device shares, then its
 * picture. Comes back by itself when the device reconnects.
 */
export function ObsView({
  room,
  device,
  fit,
  background,
  audio,
  label,
  embedded = false,
}: {
  room: string;
  device: string;
  fit: "contain" | "cover";
  background: "clear" | "black";
  audio: boolean;
  label: boolean;
  /** Inside another page (the host's preview): fills its box and leaves the page's colors alone. */
  embedded?: boolean;
}) {
  const video = useRef<HTMLVideoElement>(null);
  const [playing, setPlaying] = useState(false);
  const [status, setStatus] = useState("connecting");

  useEffect(() => {
    if (embedded) return;
    const color = background === "black" ? "#000" : "transparent";
    document.documentElement.style.background = color;
    document.body.style.background = color;
  }, [background, embedded]);

  useEffect(() => {
    const viewer = new Viewer(
      room,
      device,
      (stream) => {
        const el = video.current;
        if (!el) return;
        el.srcObject = stream;
        if (stream) void el.play().catch(() => {});
      },
      (state) => {
        setPlaying(state.playing);
        setStatus(state.status);
      },
    );
    return () => viewer.close();
  }, [room, device]);

  return (
    <div className={`${embedded ? "absolute" : "fixed"} inset-0 overflow-hidden`} data-status={status} data-playing={playing ? "yes" : "no"}>
      <video
        ref={video}
        autoPlay
        playsInline
        muted={!audio}
        className={`h-full w-full ${fit === "cover" ? "object-cover" : "object-contain"} ${playing ? "" : "invisible"}`}
      />
      {label && !playing ? (
        <p className="absolute bottom-4 left-4 rounded-full bg-black/60 px-3 py-1 font-mono text-sm text-white">
          {device} {status === "open" ? "●" : "○"}
        </p>
      ) : null}
    </div>
  );
}
