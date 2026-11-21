/* The Versely logo (the brand kit's horizontal lockup), linking home. */
export function BrandBar({ children }: { children?: React.ReactNode }) {
  return (
    <header className="mx-auto flex w-full max-w-2xl items-center justify-between gap-4 px-4 pt-5 sm:px-6">
      <a href="/" className="inline-flex items-center" aria-label="Versely">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/brand/logo.svg" alt="" width={112} height={28} className="h-7 w-auto dark:hidden" />
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/brand/logo-cream.svg" alt="" width={112} height={28} className="hidden h-7 w-auto dark:block" />
      </a>
      {children}
    </header>
  );
}
