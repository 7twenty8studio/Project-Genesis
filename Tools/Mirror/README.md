# Versely Mirror (launch show only)

Puts an iPhone's screen in OBS over Wi-Fi, with no third-party mirroring app.
A tiny app with an iOS screen broadcast extension (ReplayKit) that sends the
screen with WebRTC to the website's OBS page, `/screen/obs` (web/README.md ›
Launch-day screenshare). Not part of Versely, never on the App Store:
installed on the stage iPhones from Xcode. Free provisioning lasts 7 days;
with the paid team (4XTR53RY2V) a year.

## Install on each race iPhone

    cd ~/Desktop/7Twenty8/Project-Genesis/Tools/Mirror
    xcodegen generate
    open VerselyMirror.xcodeproj

Plug the iPhone in, pick it at the top of Xcode, scheme VerselyMirror, Run
(⌘R). First time on a phone: Settings › Privacy & Security › Developer Mode.

## On the day

1. On the Mac, OBS: one Browser source per phone, 1920 × 1080, URL from the
   app's "Copy OBS link" or from the host page
   (https://versely.7twenty8studio.com/screen/host?room=Q2TKHV33JG), which
   lists every phone that's broadcasting with its OBS link and a preview.
2. On the phone: open Versely Mirror, tap the round button, Start Broadcast,
   then open Versely. The phone shows a red pill while it's live.
3. Stop from the red pill (or Control Center).

The phone's ID (iphone-XXXX) stays the same until the app is deleted, so set
the OBS sources up once. Phones and the Mac must be on the same network; a
guest Wi-Fi that isolates devices blocks it (use a phone hotspot or the staff
network). Send-only video, about 4 Mbps per phone, H.264 when the receiver
has it (otherwise VP8).
