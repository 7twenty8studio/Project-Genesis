import { BrandBar } from "./Brand";
import { SignInButtons, SignOutButton } from "./SignIn";
import { translator, type Lang } from "@/lib/i18n";

/** All a non-member learns about a members-only sermon: that it is one. No title, no church, no outline. */
export function MembersOnly({ slug, lang, signedIn, signin }: { slug: string; lang: Lang; signedIn: boolean; signin?: string }) {
  const t = translator(lang);
  return (
    <>
      <BrandBar />
      <main className="mx-auto max-w-2xl px-4 py-16 sm:px-6">
        <h1 className="text-3xl font-semibold tracking-tight">{t("For church members")}</h1>
        {signedIn ? (
          <>
            <p className="mt-4 text-lg leading-relaxed text-muted">
              {t("This account isn't a member of the church that shared this sermon. Ask the church to add you to its group in Versely, or sign in with another account.")}
            </p>
            <div className="mt-8">
              <SignOutButton next={`/s/${slug}`} t={t} />
            </div>
          </>
        ) : (
          <>
            <p className="mt-4 text-lg leading-relaxed text-muted">
              {t("This sermon is for members of the church that shared it. Sign in with the account you use in Versely.")}
            </p>
            <div className="mt-8 max-w-sm">
              <SignInButtons next={`/s/${slug}`} t={t} status={signin} />
            </div>
          </>
        )}
      </main>
    </>
  );
}
