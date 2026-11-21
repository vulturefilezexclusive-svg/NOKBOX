# NOKBOX — Handoff / Continuation Guide

> **NOKBOX — A MUZIK JUNKIE PARADISE.** Original Flutter music & video player for young urban hip hop music junkies.
> This file is the single source of truth for any human or AI picking up the work. Keep it updated at every milestone.

_Last updated: (see git log)_ — **Status: SCAFFOLDING IN PROGRESS**

## 1. Links
- Repo (private): https://github.com/vulturefilezexclusive-svg/NOKBOX
- Feature spec page: https://cursor.com/canvas/store-cbb1d56b-1fcd-4112-8ba3-693504ccaa7e/8bf15084-ea97-498a-b783-69dcfff00435
- LRCLIB API: https://lrclib.net/docs
- AutoEQ: https://github.com/jaakkopasanen/AutoEq (MIT code; measurements by third parties — credit them)
- Audius API: https://docs.audius.co/api  (host discovery: https://api.audius.co)
- Audiomack API: https://audiomack.com/data-api/docs (OAuth 1.0a, key on request)
- Jamendo API: https://developer.jamendo.com/v3.0
- Radio Browser API: https://api.radio-browser.info/
- Podcast Index API: https://podcastindex-org.github.io/docs-api/ (+ iTunes Search API fallback, no key)
- AltStore source docs: https://faq.altstore.io/developers/make-a-source
- SideStore: https://sidestore.io  · Sideloadly: https://sideloadly.io
- media_kit (audio/video engine, libmpv): https://github.com/media-kit/media-kit

## 2. Decisions from the conversation (do not undo without the user)
- **Clean-room**: brand-new app inspired by Namida's *feature set*. Never read/copy Namida source (a Namida zip exists in the bot's attachments — never extract it). Public screenshots/README/docs.namida.app OK for inspiration only.
- **Name**: NOKBOX (all caps; "The Nokbox" estate-planning kit trademark exists in an unrelated category). Tagline: "A MUZIK JUNKIE PARADISE". Audience: YN / hood / street music junkies.
- **Icon**: Icon concept #2 (boombox cracking the ground, graffiti NB, red/black). Source: `assets/branding/icon_source.jpg`. Contains text (fine for now; later make a text-free home-screen version).
- **Default theme**: OLED pure black + red. User-changeable via HSV/HSB color wheel + H/S/V/A sliders, hex, presets, AMOLED toggle, album-art dynamic colors, theme import/export.
- **Equalizer**: own implementation (multi-band parametric/graphic + preamp + bass boost + presets + AutoEQ import), applied to BOTH local and streamed audio.
- **Sources**: Settings has a free-text "Source" field; empty/default = YouTube feed. Pluggable `SourceProvider`.
  - Allowed: YouTube (default feed; downloader = optional add-on, OFF by default / outside store builds), Audiomack (needs API key + written OK before downloads), Audius (open API; downloads only where artist allowed), Jamendo (`audiodownload_allowed` flag), Podcasts (RSS/Podcast Index/iTunes), Internet radio (Radio Browser), Internet Archive (CC/public-domain items), Custom URL / web source (stream only), local files.
  - **Removed**: SoundCloud (ToS forbids 3rd-party downloads & mixing w/o license), Tidal, Deezer (DRM; would need circumvention). Never use gdstudio music-api (it circumvents paywalls/DRM). No DRM circumvention, ever.
  - Later options: Apple MusicKit (streaming for subscribers, needs paid dev acct), Anghami SDK (per-stream billed to developer), Bandcamp (users download purchases on site; app auto-catalogs them).
- **Lyrics**: LRCLIB (set User-Agent "NOKBOX/<ver> (https://github.com/vulturefilezexclusive-svg/NOKBOX)"), offline cache. Lyrics are copyrighted: personal use only.
- **Auto source switching**: library first → download-permitted sources → other legit streams. Match by ISRC → MusicBrainz ID → fuzzy (normalized title/artist similarity, duration ±3 s, reject live/remix/sped-up/instrumental mismatches).
- **Builds**: iOS unsigned .ipa for sideloading (AltStore/SideStore/Sideloadly; free Apple ID → 7-day refresh, 3-app limit) via GitHub Actions macOS runner. **No Android APK yet** (android folder kept, not built in CI). No entitlements free accounts can't sign (no push, iCloud, app groups, CarPlay — CarPlay & widgets later). Local notifications only.

## 3. Current build status
See section 5 (updated per milestone).

## 4. What's left (prioritized)
See section 6.

## 5/6. Status & TODO — filled in below as work proceeds.
