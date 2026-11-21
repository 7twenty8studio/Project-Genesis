import Link from "next/link";
import { requestLang, requestTheme } from "@/lib/prefs.server";
import { PrefsMenu } from "./PrefsMenu";
/* The Versely logo (the brand kit's horizontal lockup), linking home, and the Appearance and Language menu. */
export async function BrandBar({ children, wide, width }: { children?: React.ReactNode; wide?: boolean; width?: string }) {
  const [lang, theme] = await Promise.all([requestLang(), requestTheme()]);
  return (
    <header className={`mx-auto flex w-full ${width ?? (wide ? "max-w-3xl" : "max-w-2xl")} items-center justify-between gap-4 px-4 pt-5 sm:px-6`}>
      <Link href="/" className="inline-flex items-center" aria-label="Versely">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/brand/logo.svg" alt="" width={112} height={28} className="h-7 w-auto dark:hidden" />
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/brand/logo-cream.svg" alt="" width={112} height={28} className="hidden h-7 w-auto dark:block" />
      </Link>
      <div className="flex items-center gap-3">
        {children}
        <PrefsMenu lang={lang} theme={theme} />
      </div>
    </header>
  );
}

/* The small print at the foot of every page. */
export function SiteFooter({ t }: { t: (s: string) => string }) {
  return (
    <footer className="border-t border-border">
      <div className="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-4 px-4 py-8 text-sm text-muted sm:px-6">
        <span className="inline-flex items-center gap-2">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/brand/symbol.svg" alt="" width={20} height={20} className="h-5 w-5" />
          {t("Versely, a Bible study app by 7twenty8 Studio.")}
        </span>
        <Link href="/studio" className="font-medium text-accent underline-offset-4 hover:underline">
          {t("Church Studio")}
        </Link>
      </div>
    </footer>
  );
}
