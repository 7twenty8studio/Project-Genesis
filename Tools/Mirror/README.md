# 7Twenty8 Mirror

Puts an iPhone's whole screen in OBS over Wi-Fi, with no third-party
mirroring app. A small app with an iOS screen broadcast extension (ReplayKit)
that sends the screen with WebRTC to OBS Sharing on 7twenty8studio.com
(Services › OBS Sharing, repo 7twenty8-studio-web, src/lib/obs-sharing).
Used for the Versely launch show's race, but not part of Versely. Never on
the App Store: installed on the iPhones from Xcode. Free provisioning lasts
7 days; with the paid team (4XTR53RY2V) a year.

The project keeps its first names (VerselyMirror target, bundle ids
com.7twenty8studio.versely.mirror…) so phones that already have it keep
their IDs. On the home screen it's "Mirror"; in iOS's broadcast sheet,
"7Twenty8 Mirror".

## Install on each iPhone

    cd ~/Desktop/7Twenty8/Project-Genesis/Tools/Mirror
    xcodegen generate
    open VerselyMirror.xcodeproj

Plug the iPhone in, pick it at the top of Xcode, scheme VerselyMirror, Run
(⌘R). First time on a phone: Settings › Privacy & Security › Developer Mode.
The app and its extension share an App Group
(group.com.7twenty8studio.mirror) for the room and name; Xcode's automatic
signing registers it. If Xcode asks, tick it under Signing & Capabilities ›
App Groups on both targets.

## Using it

The app opens with a three-step guide (the ? button shows it again):

1. **Room:** empty at first. Type the code from OBS Sharing's host page
   (the launch show's is Q2TKHV33JG) and tap Use This Room; Mirror
   remembers it. Start Broadcast waits for a room.
2. **Start Broadcast:** the big red button opens iOS's broadcast sheet on
   this app; tap Start Broadcast there. The status card says Connecting,
   Broadcasting (in the room, waiting for OBS) or Live in OBS. Switch to any
   app: it stays live. Stop from the same button or the red pill.
3. **OBS:** Copy OBS Link (or Share) gives this iPhone's Browser source,
   500 × 1080 with `fit=cover`, so the screen fills an iPhone-shaped box
   edge to edge. The host page and the OBS dock links are there too.

This iPhone's ID (iphone-XXXX) stays the same until the app is deleted.
Its name (shown on the host page and the dock) can be changed in the app.
Phones and the OBS computer must be on networks that can reach each other;
a guest Wi-Fi that isolates devices blocks it (use a phone hotspot or the
staff network). Send-only video, about 4 Mbps per phone, H.264 when the
receiver has it (otherwise VP8). A phone sends to two viewers at most; OBS
always gets one (previews give way).
