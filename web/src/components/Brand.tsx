import Link from "next/link";
/* The Versely logo (the brand kit's horizontal lockup), linking home. */
export function BrandBar({ children, wide }: { children?: React.ReactNode; wide?: boolean }) {
  return (
    <header className={`mx-auto flex w-full ${wide ? "max-w-3xl" : "max-w-2xl"} items-center justify-between gap-4 px-4 pt-5 sm:px-6`}>
      <Link href="/" className="inline-flex items-center" aria-label="Versely">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/brand/logo.svg" alt="" width={112} height={28} className="h-7 w-auto dark:hidden" />
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/brand/logo-cream.svg" alt="" width={112} height={28} className="hidden h-7 w-auto dark:block" />
      </Link>
      {children}
    </header>
  );
}
