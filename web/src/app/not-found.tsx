import { headers } from "next/headers";
import { BrandBar } from "@/components/Brand";
import { langFromHeader, translator } from "@/lib/i18n";

export default async function NotFound() {
  const t = translator(langFromHeader((await headers()).get("accept-language")));
  return (
    <>
      <BrandBar />
      <main className="mx-auto max-w-2xl px-4 py-16 sm:px-6">
        <h1 className="text-3xl font-semibold tracking-tight">{t("This page isn't available")}</h1>
        <p className="mt-4 text-lg leading-relaxed text-muted">
          {t("The link may be mistyped, or the church may have taken the sermon down.")}
        </p>
      </main>
    </>
  );
}
