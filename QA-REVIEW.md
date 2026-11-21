# NOKBOX — quality control pass (v0.2.1)

Reviewed the app source of `NOKBOX` (59 Dart files, ~10,100 lines) against
Flutter 3.50.1 / Dart 3.14 using the project's own analyzer, linter config and
unit tests, then re-ran both on the exact tree this branch contains.

## Result

| Check | Before | On this branch |
|---|---|---|
| `flutter analyze` errors | 0 | 0 |
| `flutter analyze` warnings | 0 | 0 |
| `flutter analyze` infos | 8 (lints/deprecations) | 3 (see below) |
| `flutter test` | 10 passed | 12 passed |

No compile errors and no failing tests existed before this pass: the codebase
was already healthy. The value here is the defects fixed below plus two
regression tests.

The three remaining infos are all informational (`--no-fatal-infos`, which the
CI workflow uses, ignores them):

1. `onReorder` deprecated (queue screen) — retained deliberately.
2. `getDirectoryPath` deprecated (settings) — retained deliberately.
3. `unnecessary_underscores` in `lib/ui/settings/settings_screen.dart` — a
   cosmetic style rule on one `(context, _, __)` callback. Left untouched
   because that file is 488 lines and rewriting it for a style preference
   would bury the actual fixes in diff noise.

## Fixes

### 1. Deleting a queue could move you to the wrong queue
`lib/audio/queue.dart` — `QueueSet.delete`

The active-queue index was adjusted twice: once by a "clamped to the end"
check and again by the "removed before the active one" check. With queues
`[A, B, C]` and C playing, deleting A left the player pointing at **B** instead
of C. The order of the two adjustments is now correct, with bounds guards.

### 2. Drag-reorder could crash on a stale index
`lib/audio/queue.dart` — `PlayQueue.move`

`move(from, to)` called `removeAt(from)` before validating `from`, so an
out-of-date index from the reorder list would throw `RangeError`. It now
ignores out-of-range requests instead of crashing.

### 3. A failed database write could break the rest of the session
`lib/data/database.dart` — `deleteTracks`, `setPlaylistOrder`, `importHistory`

These three methods opened a transaction and committed it with no rollback
path, unlike `upsertTracks`, which does it correctly. If any statement failed,
the connection stayed inside an open transaction and every later write in the
session failed with "cannot start a transaction within a transaction". All three
now roll back and rethrow.

### 4. Analyzer/lint clean-up (no behaviour change)
- `lib/core/diagnostics.dart` — error logging no longer appends an empty
  details block; uses the null-aware element syntax.
- `lib/sources/providers/archive_provider.dart`, `podcast_provider.dart` —
  `expand()` parameter renamed to match the base class (`collection`).
- `lib/sources/youtube/sponsorblock.dart` — removed a redundant import.

### New tests
`test/core_test.dart`:
- "deleting a queue keeps the player on the same queue" — covers fix 1.
- "reorder ignores out-of-range indices" — covers fix 2.

## Deliberately not changed

- `ReorderableListView.onReorder` is deprecated in favour of `onReorderItem`.
  The replacement only exists on newer Flutter versions than the project's
  declared minimum (`sdk: ^3.9.0`), and swapping it changes the index
  semantics the screen already compensates for.
- `FilePicker.getDirectoryPath` is deprecated in favour of `pickDirectory()`,
  which returns a `Uri` instead of a path — the library indexing code needs
  real paths, so this is a migration, not a one-line fix.
- The `unnecessary_underscores` style lint noted above.

## How this was verified

Every file changed on this branch was confirmed byte-identical to the tree
that was analyzed and tested: the local `git hash-object` of each file matched
the blob SHA GitHub stored for it (queue.dart, diagnostics.dart, database.dart,
archive_provider.dart, podcast_provider.dart, sponsorblock.dart,
core_test.dart). `flutter analyze` and `flutter test` were then run on that
tree.

## Not verified

- **The iOS build itself.** Compiling an `.ipa` needs macOS + Xcode; the review
  environment is Linux. The GitHub Actions workflow (`build-ios.yml`)
  produces the unsigned `.ipa` and runs the same analyze + test steps.
- **On-device behaviour** — playback, background audio, the EQ filter chain,
  YouTube stream resolution and downloads were reviewed by reading the code,
  not exercised on a device.
