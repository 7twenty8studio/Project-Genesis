"use client";

import { useEffect, useRef } from "react";

const COLORS = ["#f9ebd7", "#e0b48d", "#b9825a", "#f6dcb4", "#7a4e2d"];

/** A short burst of brand-coloured paper when a ticket is won. Nothing with Reduce Motion. */
export function Confetti({ burst }: { burst: number }) {
  const canvas = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const el = canvas.current;
    if (!el || burst === 0) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const ctx = el.getContext("2d");
    if (!ctx) return;
    const ratio = window.devicePixelRatio || 1;
    const width = (el.width = el.clientWidth * ratio);
    const height = (el.height = el.clientHeight * ratio);
    const pieces = Array.from({ length: 140 }, () => ({
      x: width / 2 + (Math.random() - 0.5) * width * 0.2,
      y: height * 0.42,
      vx: (Math.random() - 0.5) * width * 0.018,
      vy: -(Math.random() * 0.9 + 0.5) * height * 0.022,
      size: (Math.random() * 8 + 6) * ratio,
      spin: Math.random() * Math.PI,
      turn: (Math.random() - 0.5) * 0.3,
      color: COLORS[Math.floor(Math.random() * COLORS.length)],
    }));
    const started = performance.now();
    let frame = 0;
    const tick = (now: number) => {
      const age = (now - started) / 1000;
      ctx.clearRect(0, 0, width, height);
      ctx.globalAlpha = Math.max(0, 1 - Math.max(0, age - 2.2) / 0.8);
      for (const p of pieces) {
        p.vy += height * 0.0009;
        p.vx *= 0.99;
        p.x += p.vx;
        p.y += p.vy;
        p.spin += p.turn;
        ctx.save();
        ctx.translate(p.x, p.y);
        ctx.rotate(p.spin);
        ctx.fillStyle = p.color;
        ctx.fillRect(-p.size / 2, -p.size / 4, p.size, p.size / 2);
        ctx.restore();
      }
      if (age < 3) frame = requestAnimationFrame(tick);
      else ctx.clearRect(0, 0, width, height);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [burst]);

  return <canvas ref={canvas} aria-hidden="true" className="pointer-events-none fixed inset-0 h-full w-full" />;
}
