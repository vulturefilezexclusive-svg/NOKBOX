# NOKBOX — quality control pass (v0.2.1)

Reviewed the app source (59 Dart files, ~10,100 lines) with the project's own
analyzer, linter config and unit tests, fixed three real defects, cleaned up
lint noise and added two regression tests. Everything lives on the branch
`qa/fixes-from-review`; `main` is untouched.

Toolchain: Flutter 3.50.1 / Dart 3.14.1, `analysis_options.yaml` as committed.

## Result

| Check | Before (main) | On this branch |
|---|---|---|
| `flutter analyze` errors | 0 | **0** |
| `flutter analyze` warnings | 0 | **0** |
| `flutter analyze` infos | 8 | **2** (both retained deliberately) |
| `flutter test` | 10 passed | **12 passed** |

The codebase was already healthy: no compile errors and no failing tests. The
value here is the defects fixed below plus the two regression tests.

## Remaining analyzer output: 2 infos

Both are deprecations that were kept on purpose (reasons below):

1. `deprecated_member_use` — `onReorder` at `lib/ui/player/queue_screen.dart:144`
2. `deprecated_member_use` — `getDirectoryPath` at `lib/ui/settings/settings_screen.dart:197`

Earlier drafts of this pass also carried a third note, `unnecessary_underscores`
at `lib/ui/settings/settings_screen.dart:388`. That one is fixed: the builder is
now `(context, _, _)`. The analyzer reports nothing else.

## Fixes

### 1. Deleting a queue could move you to the wrong queue
`lib/audio/queue.dart` — `QueueSet.delete`

The active-queue index was adjusted twice: once by a "clamped to the end" check
and again by the "removed before the active one" check. With queues `[A, B, C]`
and C playing, deleting A left the player pointing at **B** instead of C — the
wrong song kept playing and the queue list highlighted the wrong row. The
adjustments now happen in the correct order, with bounds guards.

### 2. Drag-reorder could crash on a stale index
`lib/audio/queue.dart` — `PlayQueue.move`

`move(from, to)` called `removeAt(from)` before validating `from`, so an
out-of-date index from the reorder list threw `RangeError` — a red screen while
reordering. It now ignores out-of-range requests instead of crashing.

### 3. A failed database write could break the rest of the session
`lib/data/database.dart` — `deleteTracks`, `setPlaylistOrder`, `importHistory`

These three opened a transaction and committed it with no rollback path, unlike
`upsertTracks`, which does it correctly. If any statement failed, the connection
stayed inside an open transaction and every later write in the session failed
with "cannot start a transaction within a transaction" — playlists, history and
database imports silently stopped working until restart. All three now roll
back and rethrow.

### 4. Analyzer/lint clean-up (no behaviour change)
- `lib/core/diagnostics.dart` — error logging no longer appends an empty details
  block; uses the null-aware element syntax.
- `lib/sources/providers/archive_provider.dart`, `podcast_provider.dart` —
  `expand()` parameter renamed to match the base class (`collection`).
- `lib/sources/youtube/sponsorblock.dart` — removed a redundant import.
- `lib/ui/settings/settings_screen.dart` — `(context, _, __)` → `(context, _, _)`
  in the diagnostics list builder (one character; no logic touched).

### New tests
`test/core_test.dart`:
- "deleting a queue keeps the player on the same queue" — covers fix 1.
- "reorder ignores out-of-range indices" — covers fix 2.

Both fail on the old code and pass on this branch.

## Deliberately not changed

- `ReorderableListView.onReorder` is deprecated in favour of `onReorderItem`.
  The replacement is not available on the project's declared minimum
  (`sdk: ^3.9.0`), and swapping it also changes the index semantics that
  `queue_screen.dart` already compensates for — a risk to drag-to-reorder with
  no user-visible gain.
- `FilePicker.getDirectoryPath` is deprecated in favour of `pickDirectory()`,
  which returns a `Uri` instead of a path. The library indexer needs real
  paths, so this is a migration, not a one-line fix.

## How this was verified

Every file this branch changes was confirmed byte-identical to the copy that was
analyzed and tested: the local `git hash-object` of each file matched the blob
SHA GitHub stores for it.

| File | Blob SHA |
|---|---|
| `lib/audio/queue.dart` | `aa36eb92ca415a5568eb0f834d65900bef40317c` |
| `lib/core/diagnostics.dart` | `95dbadaa09ecb2bdc3e066546ab96c6d0e276076` |
| `lib/data/database.dart` | `60a0806c3aa87f9aa03df398f8e065b1ac1ec8e6` |
| `lib/sources/providers/archive_provider.dart` | `03e118bd0f6c1b4a20cb169e28f09c9252813d85` |
| `lib/sources/providers/podcast_provider.dart` | `daf6912f1bdef3888e2a6524fd563c1c5e731424` |
| `lib/sources/youtube/sponsorblock.dart` | `46b1a6e5d1f6db5d706f494c064b8f52b6fbb21d` |
| `lib/ui/settings/settings_screen.dart` | `2a3d4259fd10aa779fc3e308e3a7c97ca2fb5ed4` |
| `test/core_test.dart` | `02cca87ca0a54273b03a26ab0f466f04ca58f0a7` |

Commands run on that tree:

```
flutter analyze   -> 0 errors, 0 warnings, 2 infos
flutter test      -> 12 passed, 0 failed
```

(`flutter analyze` exits non-zero when any issue is present; the CI workflow
runs it with `--no-fatal-infos --no-fatal-warnings`, so the two informational
deprecations do not fail the build.)

## Not verified

- **The iOS build itself.** Compiling an `.ipa` needs macOS + Xcode; this review
  ran on Linux. The GitHub Actions workflow (`.github/workflows/build-ios.yml`)
  produces the unsigned `.ipa` and runs the same analyze + test steps.
- **On-device behaviour.** The app was never run on a device, so playback,
  background/lock-screen audio, the equalizer filter chain, YouTube stream
  resolution and downloads were reviewed by reading the code, not exercised.
  Those need a device test after install.
