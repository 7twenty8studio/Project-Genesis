# Versely on the web (versely.7twenty8studio.com)

Church Studio and the guest sermon page for church sermons (VRS-18).
The rules, the database and going live are in ../CHURCH_SERMONS.md.

Next.js 16 (App Router, Turbopack), React 19, Tailwind 4: the same stack as
the 7twenty8 site. This version differs from older Next.js: read
`node_modules/next/dist/docs` before changing routing, caching or the proxy.

    npm install
    npm run dev          # http://localhost:3000
    npm test             # Node tests for src/lib (no browser, no network)
    npm run lint
    npm run build
    ./e2e/run.sh         # browser checks against a stand-in server (e2e/run.sh says how)

| Route | What |
| --- | --- |
| `/s/<slug>` | A published sermon, as the visitor may see it now (never cached) |
| `/s/<slug>/cover` | Its cover, from the `sermon-cover` function (access rechecked on every request, never a signed link) |
| `/studio` | Church Studio: sign in, pick a church, its sermons and reports; People (roles) and settings for the owner and admins, a preacher's own view |
| `/studio/<id>` | One sermon: Outline (import, edit), Details, Preview, Share |
| `/auth/start`, `/auth/callback`, `/auth/signout` | Sign in with Apple or Google (Supabase PKCE) |
| `/auth/password` | Sign in with the app's email and password, or send the reset email (form post) |
| `/.well-known/apple-app-site-association` | Universal Links for `/s/*` |
| `/launch` | Launch day giveaway entry (phones by QR; `?kiosk=1` on the lobby iPad clears itself for the next person) |
| `/launch/host` | The projector page: live draw of volunteers and the final golden ticket, the game timer, a paper-ticket draw without internet (ops admins only; 20261127000000) |

- No Supabase SDK and no secrets: the public anon key and the person's own
  token (src/config.ts); the database decides everything.
- `src/lib/shared/` is a copy of supabase/functions/_shared/references.ts
  and bibleBooks.json (`npm run sync`; a test fails when they differ).
- Words on screen: write English in `t("…")`, add Spanish (tú) and
  Brazilian Portuguese (você) to `src/lib/messages.ts`. `node
  scripts/strings.mjs` lists every string; the test checks them.
- Scripture is never typed here: passages load verbatim from the
  `bibles/web/v1` files (Tools/BibleData/export_web_chapters.py).
