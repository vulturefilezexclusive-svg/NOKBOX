NOKBOX — CHANGES v2 (round 2)   updated 2026-11-21 ~2:20 AM CST
Repo:    https://github.com/vulturefilezexclusive-svg/NOKBOX  (private, branch main)
Actions: https://github.com/vulturefilezexclusive-svg/NOKBOX/actions
Round-2 run #1 (commit "YouTube: multi-client stream fallback..."): https://github.com/vulturefilezexclusive-svg/NOKBOX/actions/runs/44880024603

== DONE (pushed) ==
1. YouTube streams fixed (root cause found)
   - The old code asked YouTube for streams with only the "safari" + "androidVr" clients.
     Tested live: androidVr says "unplayable", safari returns cipher URLs with no host -> every play failed.
     The ANDROID / android_sdkless clients return working audio (HTTP 206 verified).
   - Now tries 6 clients in order (android_sdkless, android, ios, tv, android_vr, safari), PROBES each
     URL (1 KB range request) before giving it to the player, and sends the matching User-Agent header
     to mpv. Manifests are cached 4 h. Audio = best AAC/m4a; video = HLS if offered, else muxed mp4.
   - All client failures are written to Diagnostics.
   Files: lib/sources/providers/youtube_provider.dart
2. YouTube downloader is built in (no flag, no "store-safe" text)
   - Every YouTube item is downloadable. Default = audio m4a; Settings > Sources > YouTube > "Download as video" = mp4.
   - Downloads are fetched in 9 MB ranges (YouTube cuts long single requests); saved to
     Documents/NOKBOX Downloads/<artist>/ and picked up by the Library rescan.
   Files: youtube_provider.dart, lib/sources/download_manager.dart, lib/core/settings.dart, lib/ui/settings/settings_screen.dart
3. Audiomack, Jamendo, Audius removed (provider files deleted; settings keys, setup fields, credits, hints, matcher preference removed)
   Files: lib/sources/source_registry.dart, source_matcher.dart, data/models.dart, core/settings.dart, ui/settings/settings_screen.dart, ui/screens/feed_screen.dart
4. Namida mention + disclaimers removed (About now just "Version 0.2.0"; YouTube ToS blurb and "Not included in this build" gone).
   Credits remain only in About > Credits / Open-source licenses.
5. Diagnostics engine (logic done; Settings button = see TODO)
   - lib/core/diagnostics.dart: ring buffer (2000 events) from launch + session temp file. First error
     (uncaught exception, Flutter error, failed playback, failed download, YouTube failure) flags the
     session and writes a permanent report-<time>.txt. Clean session buffer is deleted on clean exit and next launch.
   - Hooks installed in lib/main.dart (runZonedGuarded + FlutterError + PlatformDispatcher).
   - API: Diag.info/warn/error, Diag.exportBundle(), Diag.clear(), Diag.reports().
6. YouTube sign-in plumbing: lib/sources/youtube/youtube_account.dart (cookies in iOS Keychain via
   flutter_secure_storage, SAPISIDHASH auth for InnerTube, profile fetch, sign-out). The Home feed already
   uses it: signed in -> your real YouTube "Recommended" + "From your subscriptions"; signed out ->
   YouTube's anonymous home + "Because you played X" (related videos to your history) + "More from <top artist>"
   + trending hip hop / trap / drill / R&B shelves.
   New packages: flutter_secure_storage, webview_cookie_manager_plus, audio_session.
7. EQ FX (reverb, stereo width, virtualizer, 3D)
   - EqProfile gains reverbAmount/room/damping/wet, stereoWidth, virtualizer, threeD — all default off,
     so existing profiles sound identical. MpvEqBuilder appends aecho / extrastereo / bs2b / apulsator
     to the same @nokeq lavfi chain; EqualizerController setters rebuild the chain the same way EQ
     does (live, no playback interruption).
   - Equalizer screen gains an "FX" tab with sliders + reset. EQ button in the mini player and the
     full player opens the EQ as a bottom sheet (showEqBottomSheet) without touching playback.
   Files: lib/audio/eq.dart, lib/audio/mpv_filters.dart, lib/audio/equalizer_controller.dart,
   lib/ui/settings/equalizer_screen.dart, lib/ui/player/mini_player.dart, lib/ui/player/full_player.dart

== STILL TO DO (in order) — see HANDOFF.md ==
a. Navigation: Home tab -> show FeedScreen (YouTube feed + "Source" switch button); 4th tab "Feed" -> "Playlists"
   (reuse _PlaylistsTab from library_screen.dart: create; PlaylistScreen already has rename/delete).
   File: lib/ui/root_shell.dart
b. Settings > YouTube account screen: WebView to https://accounts.google.com/ServiceLogin?continue=https://www.youtube.com,
   when URL reaches youtube.com read cookies with WebviewCookieManager().getCookies('https://www.youtube.com'),
   join "name=value; ..." and call nok.ytAccount.save(...) then refreshProfile(); sign-out button -> signOut().
   (Google may block embedded login; fallback = paste cookies / import Takeout subscriptions.)
c. Settings > Diagnostics tile: "Export diagnostic" -> SharePlus.instance.share(ShareParams(files:[XFile((await Diag.exportBundle()).path)])); "Clear" -> Diag.clear().
   Call Diag.cleanExit() on AppLifecycleState.detached in root_shell.dart.
e. Animated splash: new lib/ui/splash_screen.dart (AnimationController pulsing speaker icon + glowing NOKBOX text, 1.8 s) shown before RootShell in app.dart.
f. Background/lock screen: Info.plist already has UIBackgroundModes=audio; add AudioSession.instance configure(AudioSessionConfiguration.music()) in main.dart; audio_service handler already wired (lib/audio/audio_handler.dart). Test on device.

== HOW TO PROCEED ==
1. Wait for the Actions run to go green, open it, download artifact "NOKBOX-ipa-<sha>" (NOKBOX.ipa), install with AltStore/SideStore/Sideloadly.
2. Test YouTube playback first. If a song still fails: Settings > Diagnostics > Export (once item c is done) and send the log.
3. Another AI: clone repo, `flutter pub get && flutter analyze && flutter test`, do TODO a–f, push to main (CI builds the .ipa automatically).
