"use client";

import type { ButtonHTMLAttributes, ReactNode } from "react";

export function Button({ primary, danger, className = "", ...props }: ButtonHTMLAttributes<HTMLButtonElement> & { primary?: boolean; danger?: boolean }) {
  const look = primary
    ? "bg-accent-strong text-on-accent hover:opacity-90"
    : danger
      ? "border border-border bg-surface text-[#9b2c1f] hover:bg-surface-2 dark:text-[#ffb4a6]"
      : "border border-border bg-surface text-foreground hover:bg-surface-2";
  return (
    <button
      type="button"
      {...props}
      className={`inline-flex min-h-11 items-center justify-center gap-2 rounded-full px-5 font-medium disabled:cursor-not-allowed disabled:opacity-50 ${look} ${className}`}
    />
  );
}

export function Notice({ children, tone = "alert" }: { children: ReactNode; tone?: "alert" | "status" }) {
  return (
    <div role={tone} className="mt-4 rounded-2xl border border-border bg-surface-2 p-4 leading-relaxed">
      {children}
    </div>
  );
}

/** A labelled field. `hintBelow` puts the hint under the box, so boxes side by side line up. */
export function Field({ label, hint, hintBelow, children, id }: { label: string; hint?: string; hintBelow?: boolean; children: ReactNode; id: string }) {
  const hintText = hint ? (
    <p id={`${id}-hint`} className={`${hintBelow ? "mt-2" : "mt-1"} text-sm text-muted`}>
      {hint}
    </p>
  ) : null;
  return (
    <div className="mt-5">
      <label htmlFor={id} className="block font-medium">
        {label}
      </label>
      {hintBelow ? null : hintText}
      <div className="mt-2">{children}</div>
      {hintBelow ? hintText : null}
    </div>
  );
}

export const inputClass = "w-full rounded-xl border border-border bg-surface px-3 py-2.5 text-base text-foreground placeholder:text-muted";
