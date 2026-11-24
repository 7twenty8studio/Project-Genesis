# Mirror OBS

Puts an iPhone's whole screen in OBS over Wi-Fi: a small app with an iOS
screen broadcast extension (ReplayKit) that sends the screen with WebRTC to
OBS Sharing on 7twenty8studio.com (Services › OBS Sharing, repo
7twenty8-studio-web, src/lib/obs-sharing). A 7Twenty8 Studio app for the
App Store, not part of Versely. Tools/Mirror is the earlier build used for
the Versely launch show (installed from Xcode); this is its App Store copy
with its own names, so the two can sit side by side.

- Name: Mirror OBS (home screen and broadcast sheet). "OBS" belongs to the
  OBS Project: the listing says it works with OBS Studio and isn't made by
  or affiliated with it. If App Review or the OBS Project objects, the
  fallback name is "Mirror for OBS".
- Bundle ids: com.7twenty8studio.mirrorobs and
  com.7twenty8studio.mirrorobs.broadcast; App Group
  group.com.7twenty8studio.mirrorobs. Team 4XTR53RY2V.
- Price: free download, 7-day free trial, then a one-time $4.99 unlock.
- Privacy: no account, no analytics, nothing collected. The screen goes
  peer to peer (WebRTC) to the OBS computer; only the signalling (room code,
  device ID, name, connection offers) passes through a public Supabase
  Realtime channel and isn't stored. Privacy manifests in Privacy/ declare
  UserDefaults (CA92.1, 1C8F.1 for the App Group).

## Build and run

    cd ~/Desktop/7Twenty8/Project-Genesis/Tools/MirrorOBS
    xcodegen generate
    open MirrorOBS.xcodeproj

Scheme MirrorOBS, pick the iPhone, Run (⌘R). The scheme uses
MirrorOBS.storekit, so the trial, the unlock, Restore and Ask to Buy work
in Xcode without App Store Connect (Debug › StoreKit › Manage Transactions
to delete a purchase and start over, or to move time on to end the trial).
The screen broadcast itself only works on a real iPhone.

## How the trial and unlock work (Store.swift)

- `com.7twenty8studio.mirrorobs.trial7`: a $0 **non-renewing
  subscription** called "7-Day Free Trial". This is Apple's way to offer a
  free trial before a one-time purchase (guideline 3.1.1). The 7 days are
  counted from its purchase date, on every device of that Apple Account,
  and it can't be started again (it stays in the account's history).
- `com.7twenty8studio.mirrorobs.unlock`: a $4.99 **non-consumable**,
  "Unlock Mirror OBS", Family Sharing on.
- The app reads `Transaction.all` on launch, on return and after every
  purchase, and writes "unlocked" or the trial's end into the App Group.
  The broadcast extension checks it when a broadcast starts and stops with
  "Your free trial has ended. Open Mirror OBS to unlock it." A broadcast
  already running when the trial ends keeps going until it's stopped.
- Restore Purchases (`AppStore.sync`) and Redeem Code (Apple's offer code
  sheet) are on the trial card.

## Free copies (the owner, friends, reviewers)

Apple doesn't allow an app's own codes or a private list of "premium users"
for unlocking features (3.1.1), so free copies are **offer codes** for the
unlock:

1. App Store Connect › Mirror OBS › In-App Purchases › Unlock Mirror OBS ›
   Offer Codes › create an offer (free), then either a custom code (e.g.
   7TWENTY8FAMILY with a redemption limit) or up to 1,000 one-time codes.
2. Each person types the code in Mirror OBS › Redeem Code (or the App
   Store's Redeem link). It arrives as an ordinary unlock, on all their
   devices, for good, and Restore brings it back.

Offer codes for one-time purchases need iOS 18 or later to redeem in the
app; on iOS 17, redeem in the App Store app (Account › Redeem Gift Card or
Code). Before release, TestFlight testers get both purchases free in the
sandbox anyway.

## App Store Connect checklist

1. Certificates, Identifiers & Profiles: register both bundle ids and the
   App Group (Xcode's automatic signing can do it on first Run).
2. New app: name "Mirror OBS", primary language English (U.S.), bundle id
   com.7twenty8studio.mirrorobs, SKU MIRROROBS1, category Photo & Video
   (secondary: Utilities). Price: free.
3. In-App Purchases: the non-renewing subscription and the non-consumable
   above, with the exact product ids, a review screenshot of the trial card,
   and review notes. Add both to the first version's submission.
4. App Privacy: Data Not Collected. Privacy Policy URL:
   https://www.7twenty8studio.com/services/obs-sharing/mirror/privacy .
   Support URL: https://www.7twenty8studio.com/services/obs-sharing/mirror .
5. Export compliance: answered in Info.plist (standard encryption only).
6. Review notes: explain that it needs a computer with OBS (or any browser)
   at https://www.7twenty8studio.com/services/obs-sharing , give a room code
   to try, and say a screen recording of it working is attached.
7. Archive: Product › Archive in Xcode, Distribute › App Store Connect.

Listing text (description, keywords, promotional text) is in
APP_STORE.md.

## Using it

The app opens with a three-step guide (the ? button shows it again):

1. **Room:** empty at first. Type the code from OBS Sharing's host page and
   tap Use This Room; Mirror OBS remembers it.
2. **Start Broadcast:** opens iOS's broadcast sheet on this app; tap Start
   Broadcast there. The status card says Connecting, Broadcasting or Live in
   OBS. Switch to any app: it stays live. Stop from the same button or the
   red pill.
3. **OBS:** Copy OBS Link gives this iPhone's Browser source, 500 × 1080
   with `fit=cover`. The host page and the OBS dock links are there too.

This iPhone's ID (iphone-XXXX) stays the same until the app is deleted.
Phones and the OBS computer must be on networks that can reach each other;
a guest Wi-Fi that isolates devices blocks it. Send-only video, about
4 Mbps, H.264 when the receiver has it (otherwise VP8). A phone sends to two
viewers at most; OBS always gets one (previews give way).
