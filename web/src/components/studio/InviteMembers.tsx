"use client";

import { useState, useTransition } from "react";
import { newInviteCode } from "@/app/studio/actions";
import { translator, type Lang } from "@/lib/i18n";
import { formatInviteCode } from "@/lib/invite";
import { refusalMessage } from "@/lib/studio";
import { Button, Notice } from "./ui";

/**
 * The church's group invite code, as on the app's Members tab: members join
 * in Versely (Together › Join with an Invite Code) and then read the
 * church's members-only sermons. Owner and moderators can make a new code.
 */
export function InviteMembers({ lang, church, name, code, requiresApproval }: { lang: Lang; church: string; name: string; code: string; requiresApproval: boolean }) {
  const t = translator(lang);
  const [current, setCurrent] = useState(code);
  const [pending, start] = useTransition();
  const [message, setMessage] = useState<{ text: string; tone: "alert" | "status" } | null>(null);
  const shown = formatInviteCode(current);
  const invite = t("Join {name} on Versely to read and pray together. Open Together › Join with an Invite Code and enter {code}.", { name, code: shown });

  const copy = async (text: string, done: string) => {
    try {
      await navigator.clipboard.writeText(text);
      setMessage({ text: done, tone: "status" });
    } catch {
      setMessage({ text: t("Couldn't copy. Select the code and copy it yourself."), tone: "alert" });
    }
  };
  const share = async () => {
    if (typeof navigator.share === "function") {
      try {
        await navigator.share({ text: invite });
        return;
      } catch (error) {
        if (error instanceof DOMException && error.name === "AbortError") return;
      }
    }
    await copy(invite, t("Invitation copied. Paste it into a text or email."));
  };
  const renew = () =>
    start(async () => {
      setMessage(null);
      const result = await newInviteCode(church);
      if (result.ok) {
        setCurrent(result.code);
        setMessage({ text: t("New code made. The old one no longer works."), tone: "status" });
      } else setMessage({ text: t(refusalMessage(result.code)), tone: "alert" });
    });

  return (
    <section aria-labelledby="invite" className="mt-8 rounded-3xl border border-border bg-surface p-5">
      <h2 id="invite" className="text-lg font-semibold">
        {t("Invite members")}
      </h2>
      <p className="mt-1 text-sm text-muted">
        {t("Members join in the Versely app with this code. Then they can read your members-only sermons.")}
      </p>
      <div className="mt-4 flex flex-wrap items-center gap-3">
        <span className="text-sm font-medium">{t("Invite code")}</span>
        <code data-testid="invite-code" className="select-all rounded-xl bg-surface-2 px-4 py-2 font-mono text-xl font-semibold tracking-wider">
          {shown}
        </code>
      </div>
      <div className="mt-4 flex flex-wrap gap-3">
        <Button primary disabled={pending} onClick={share}>
          {t("Invite People")}
        </Button>
        <Button disabled={pending} onClick={() => copy(shown, t("Code copied."))}>
          {t("Copy code")}
        </Button>
        <Button disabled={pending} onClick={renew}>
          {pending ? t("Making a new code…") : t("New Code")}
        </Button>
      </div>
      <p className="mt-3 text-sm text-muted">
        {requiresApproval ? t("Anyone with the code can ask to join, and a moderator lets them in.") : t("Anyone with the code can join. Make a new code to stop the old one working.")}
      </p>
      {message ? <Notice tone={message.tone}>{message.text}</Notice> : null}
    </section>
  );
}
