import { config } from "@/config";
import type { Translate } from "@/lib/i18n";

/**
 * Sign in with Apple (first, as in the app, once its web Services ID is set
 * up: config.appleWebSignIn) or Google; comes back to `next`. Signing in the
 * first time makes the account, the same one the app uses.
 */
export function SignInButtons({ next, t }: { next: string; t: Translate }) {
  const href = (provider: string) => `/auth/start?provider=${provider}&next=${encodeURIComponent(next)}`;
  return (
    <div className="flex flex-col gap-3">
      {config.appleWebSignIn ? (
        <a
          href={href("apple")}
          className="inline-flex min-h-12 items-center justify-center gap-2 rounded-full bg-black px-6 text-base font-medium text-white hover:bg-neutral-800 dark:bg-white dark:text-black dark:hover:bg-neutral-200"
        >
          <svg aria-hidden="true" width="16" height="19" viewBox="0 0 16 19" fill="currentColor">
            <path d="M13.2 10.1c0-2.4 2-3.6 2.1-3.7-1.1-1.7-2.9-1.9-3.5-1.9-1.5-.2-2.9.9-3.7.9-.8 0-1.9-.9-3.2-.8-1.6 0-3.1 1-4 2.4-1.7 3-.4 7.4 1.2 9.8.8 1.2 1.8 2.5 3 2.4 1.2 0 1.7-.8 3.1-.8 1.5 0 1.9.8 3.2.8 1.3 0 2.2-1.2 3-2.4.9-1.4 1.3-2.7 1.3-2.8 0 0-2.5-1-2.5-3.9zM10.8 3c.7-.8 1.1-1.9 1-3-1 0-2.1.7-2.8 1.5-.6.7-1.2 1.8-1 2.9 1 .1 2.1-.6 2.8-1.4z" />
          </svg>
          {t("Continue with Apple")}
        </a>
      ) : null}
      <a
        href={href("google")}
        className="inline-flex min-h-12 items-center justify-center gap-2 rounded-full border border-border bg-surface px-6 text-base font-medium text-foreground shadow-sm transition-colors hover:bg-surface-2"
      >
        <svg aria-hidden="true" width="18" height="18" viewBox="0 0 18 18">
          <path fill="#4285F4" d="M17.6 9.2c0-.6-.1-1.2-.2-1.8H9v3.4h4.8a4.1 4.1 0 0 1-1.8 2.7v2.2h2.9c1.7-1.6 2.7-3.9 2.7-6.5z" />
          <path fill="#34A853" d="M9 18c2.4 0 4.5-.8 6-2.2l-2.9-2.2c-.8.5-1.8.9-3.1.9-2.4 0-4.4-1.6-5.1-3.8H.9v2.3A9 9 0 0 0 9 18z" />
          <path fill="#FBBC05" d="M3.9 10.7a5.4 5.4 0 0 1 0-3.4V5H.9a9 9 0 0 0 0 8z" />
          <path fill="#EA4335" d="M9 3.6c1.3 0 2.5.5 3.5 1.4l2.6-2.6A9 9 0 0 0 .9 5l3 2.3C4.6 5.2 6.6 3.6 9 3.6z" />
        </svg>
        {t("Continue with Google")}
      </a>
    </div>
  );
}

export function SignOutButton({ next, t }: { next: string; t: Translate }) {
  return (
    <form action="/auth/signout" method="post">
      <input type="hidden" name="next" value={next} />
      <button type="submit" className="whitespace-nowrap text-sm font-medium text-accent underline-offset-4 hover:underline">
        {t("Sign out")}
      </button>
    </form>
  );
}
