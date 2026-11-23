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

## Launch-day screenshare (/screen)

Our own screenshare into OBS, so no App Store mirroring app is needed.

- `/screen/host` (the person running OBS): makes a room (kept in this browser), shows its share link and QR, lists every device in the room with its own OBS link and a live preview.
- `/screen?room=…` (each device): the device gets its own ID (kept on the device; `&device=stage-laptop` fixes one, so OBS can be set up beforehand), then Share my screen, or Back/Front camera.
- `/screen/obs?room=…&device=…` (an OBS Browser source, 1920 × 1080): only the picture, clear background until the device shares, back by itself when the device reconnects. Options: `fit=cover`, `bg=black`, `audio=1` (then tick Control audio via OBS), `label=1`.

How it works: WebRTC peer to peer (on the venue's network the picture goes straight from the device to the Mac, nothing is stored); offers, answers and ICE candidates go through a public Supabase Realtime broadcast channel `versely-screen-<room>` (lib/screenshare/room.ts, plain WebSocket, no table, no migration). Anyone who knows the room can join it, so keep the room code to the people on stage. Public STUN only, no TURN: a network with client isolation (some guest Wi-Fi) blocks it; then use a phone hotspot or the venue's staff network.

iPhone and iPad can't share their screen from any web page (no getDisplayMedia in iOS). They can share a camera here; for their screens use the Mac's AirPlay Receiver (Screen Mirroring, then a macOS Screen Capture source in OBS) or a USB cable (the iPhone shows up as a Video Capture Device in OBS).
