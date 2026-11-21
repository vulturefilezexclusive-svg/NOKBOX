import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nokbox/audio/audio_backend.dart';
import 'package:nokbox/audio/autoeq.dart';
import 'package:nokbox/audio/eq.dart';
import 'package:nokbox/audio/mpv_filters.dart';
import 'package:nokbox/audio/queue.dart';
import 'package:nokbox/core/settings.dart';
import 'package:nokbox/core/theme/nok_theme.dart';
import 'package:nokbox/data/database.dart';
import 'package:nokbox/data/models.dart';
import 'package:nokbox/library/indexer.dart';
import 'package:nokbox/library/library_controller.dart';
import 'package:nokbox/library/text_utils.dart';
import 'package:nokbox/lyrics/lrc.dart';
import 'package:nokbox/sources/download_manager.dart';
import 'package:nokbox/sources/providers/custom_provider.dart';
import 'package:nokbox/sources/source_matcher.dart';
import 'package:nokbox/sources/source_provider.dart';
import 'package:nokbox/sources/source_registry.dart';
import 'package:nokbox/sources/youtube/sponsorblock.dart';
import 'package:path/path.dart' as p;

Track t(String id, {String title = 't', String artist = 'a', int ms = 180000}) => Track(id: id, uri: id, title: title, artist: artist, durationMs: ms);

void main() {
  test('stock theme is OLED black + red and round-trips', () {
    expect(NokThemeSpec.stock.background, const Color(0xFF000000));
    expect(colorToHex(NokThemeSpec.stock.accent), '#FFE5121B');
    final back = NokThemeSpec.fromJson(NokThemeSpec.stock.toJson());
    expect(back.accent, NokThemeSpec.stock.accent);
    expect(hexToColor('#E5121B'), const Color(0xFFE5121B));
  });

  test('AutoEQ parametric parse + mpv chain', () {
    const txt = 'Preamp: -6.2 dB\nFilter 1: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.70\nFilter 2: ON PK Fc 2200 Hz Gain -3.1 dB Q 1.41\n';
    final p = AutoEqParser.parse(txt, name: 'x');
    expect(p.preampDb, -6.2);
    expect(p.bands.length, 2);
    expect(p.bands.first.type, EqFilterType.lowShelf);
    final chain = const MpvEqBuilder().build(p);
    expect(chain, startsWith('@nokeq:lavfi=['));
    expect(chain, contains('equalizer=f=2200:t=q:w=1.41:g=-3.1'));
    expect(const MpvEqBuilder().build(EqProfile.flat), '');
  });

  test('artist parsing splits separators and feat.', () {
    final p = ArtistParser(separators: [',', ' & ', ' x ']);
    expect(p.split('Future & Metro Boomin', title: 'Like That (feat. Kendrick Lamar)'), ['Future', 'Metro Boomin', 'Kendrick Lamar']);
    expect(p.split('Drake ft. 21 Savage'), ['Drake', '21 Savage']);
  });

  test('fuzzy search tolerates typos', () {
    expect(fuzzyContains('Kendrick Lamar Not Like Us', 'kendrik'), isTrue);
    expect(fuzzyContains('Kendrick Lamar Not Like Us', 'zzz'), isFalse);
  });

  test('LRC parsing incl. multiple stamps and offset', () {
    final l = parseLrc('[offset:+100]\n[00:01.00][00:05.50]Yeah\n[00:03.20]Uh huh');
    expect(l.lines.length, 3);
    expect(l.lines[1].text, 'Uh huh');
    expect(l.indexAt(const Duration(seconds: 4)), 1);
  });

  test('matcher: duration window and version mismatch', () {
    final want = t('a', title: 'HUMBLE.', artist: 'Kendrick Lamar', ms: 177000);
    expect(SourceMatcher.score(want, t('b', title: 'HUMBLE. (Official Video)', artist: 'Kendrick Lamar', ms: 179000)), greaterThan(0.82));
    expect(SourceMatcher.score(want, t('c', title: 'HUMBLE. (Live)', artist: 'Kendrick Lamar', ms: 177000)), 0);
    expect(SourceMatcher.score(want, t('d', title: 'HUMBLE.', artist: 'Kendrick Lamar', ms: 190000)), 0);
  });

  test('queues: play next, shuffle restore, repeat', () {
    final q = PlayQueue(id: '1', name: 'Q', items: [t('1'), t('2'), t('3')]);
    q.playNext([t('x')]);
    expect(q.items[1].id, 'x');
    q.setShuffle(true);
    expect(q.current!.id, '1');
    q.setShuffle(false);
    expect(q.items.map((e) => e.id).toList(), ['1', 'x', '2', '3']);
    q.index = 3;
    expect(q.nextIndex(), isNull);
    q.repeat = RepeatMode.all;
    expect(q.nextIndex(), 0);
    final set = QueueSet.decode(QueueSet(queues: [q]).encode());
    expect(set.current.items.length, 4);
  });

  test('database FTS + history + playlists', () {
    final db = NokDatabase.memory();
    db.upsertTracks([t('local:/a.mp3', title: 'Money Trees', artist: 'Kendrick Lamar')]);
    expect(db.searchIds('money'), ['local:/a.mp3']);
    db.logPlay(t('local:/a.mp3'), 60000);
    expect(db.playCount('local:/a.mp3'), 1);
    final id = db.createPlaylist('Car');
    db.addToPlaylist(id, [t('local:/a.mp3')]);
    expect(db.playlists().first.trackIds, ['local:/a.mp3']);
  });

  test('deleting a queue keeps the player on the same queue', () {
    final set = QueueSet(
      queues: [
        PlayQueue(id: 'a', name: 'A', items: [t('1')]),
        PlayQueue(id: 'b', name: 'B', items: [t('2')]),
        PlayQueue(id: 'c', name: 'C', items: [t('3')]),
      ],
      active: 2,
    );
    set.delete(0); // delete a queue below the active one
    expect(set.current.id, 'c');
    set.delete(1); // delete the active queue itself
    expect(set.current.id, 'b');
  });

  test('reorder ignores out-of-range indices', () {
    final q = PlayQueue(id: '1', name: 'Q', items: [t('1'), t('2')]);
    q.move(0, 5);
    q.move(-1, 0);
    expect(q.items.map((e) => e.id).toList(), ['1', '2']);
  });

  test('M3U parsing', () {
    final r = CustomUrlProvider.parsePlaylist('#EXTM3U\n#EXTINF:-1,Hot 97\nhttp://x/s.mp3\n', Uri.parse('http://x/'));
    expect(r.single.$2, 'Hot 97');
  });

  test('SponsorBlock hash prefix + parse', () {
    expect(SponsorBlockClient.hashPrefix('dQw4w9WgXcQ').length, 4);
    final segs = SponsorBlockClient.parse('[{"videoID":"v1","segments":[{"category":"sponsor","segment":[10.5,20],"UUID":"u","actionType":"skip"}]},{"videoID":"v2","segments":[]}]', 'v1');
    expect(segs.single.start, const Duration(milliseconds: 10500));
  });

  test('most played sorts from one play-count query', () {
    final db = NokDatabase.memory();
    final a = t('a'), b = t('b'), c = t('c');
    db.logPlay(a, 1000);
    db.logPlay(b, 1000);
    db.logPlay(b, 1000);
    final lib = LibraryController(
      db: db,
      settings: SettingsStore.memory(),
      documentsDir: '/tmp/nokbox-test/docs',
      artDir: '/tmp/nokbox-test/art',
    );
    addTearDown(lib.dispose);
    expect(db.playCounts(), {'a': 1, 'b': 2});
    expect(lib.sorted([a, b, c], TrackSort.mostPlayed).map((e) => e.id).toList(), ['c', 'a', 'b']);
    expect(lib.sorted([c, a, b], TrackSort.mostPlayed, desc: true).map((e) => e.id).toList(), ['b', 'a', 'c']);
  });

  test('indexer reports files that no longer pass the size filter', () async {
    final dir = Directory.systemTemp.createTempSync('nokbox-index-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final big = File(p.join(dir.path, 'big.mp3'))..writeAsBytesSync(List.filled(4096, 0));
    final small = File(p.join(dir.path, 'small.mp3'))..writeAsBytesSync(List.filled(64, 0));
    final bigId = 'local:${big.path}';
    final smallId = 'local:${small.path}';
    final r = await runIndexer(IndexOptions(
      roots: [dir.path],
      excluded: const [],
      artDir: p.join(dir.path, 'art'),
      minSizeKb: 1,
      known: {bigId: 1, smallId: 1},
    ));
    expect(r.removedIds, contains(smallId));
    expect(r.removedIds, isNot(contains(bigId)));
    expect(r.added.map((e) => e.id), contains(bigId));
  });

  test('a changed minimum duration re-reads files instead of trusting mtimes', () async {
    final dir = Directory.systemTemp.createTempSync('nokbox-scan-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File(p.join(dir.path, 'Artist - Song.mp3'))..writeAsBytesSync(List.filled(4096, 0));
    final settings = SettingsStore.memory({
      'libraryFolders': [dir.path],
      'minSizeKb': 1,
      'minDurationSec': 60,
    });
    final db = NokDatabase.memory();
    final lib = LibraryController(
      db: db,
      settings: settings,
      documentsDir: p.join(dir.path, 'docs'),
      artDir: p.join(dir.path, 'art'),
    );
    addTearDown(lib.dispose);
    db.kvSet('library.indexedMinDurationSec', '30'); // catalog built with a 30 s floor
    final first = await lib.rescan();
    expect(first!.unchanged, 0);
    expect(first.added.map((e) => e.id), contains('local:${file.path}'));
    expect(db.kvGet('library.indexedMinDurationSec'), '60');
    final second = await lib.rescan();
    expect(second!.unchanged, 1);
    expect(second.added, isEmpty);
  });

  test('a truncated download fails instead of being marked done', () async {
    final dir = Directory.systemTemp.createTempSync('nokbox-dl-');
    addTearDown(() => dir.deleteSync(recursive: true));
    var finished = false;
    final manager = DownloadManager(
      registry: SourceRegistry(SettingsStore.memory(), providers: [_FakeProvider()]),
      downloadsDir: dir.path,
      onFinished: () async => finished = true,
      client: MockClient.streaming((request, body) async => http.StreamedResponse(
            Stream<List<int>>.value(List.filled(500, 0)),
            200,
            contentLength: 1000,
            headers: {'content-type': 'audio/mpeg'},
          )),
    );
    addTearDown(manager.dispose);
    final track = Track(id: 'fake:1', uri: 'https://example.test/1.mp3', title: 'Song', artist: 'Artist', source: 'fake');
    await manager.request(track);
    final task = manager.tasks.single;
    for (var i = 0; i < 200; i++) {
      if (task.status != DownloadStatus.running && task.status != DownloadStatus.queued) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(task.status, DownloadStatus.failed);
    expect(task.error, contains('Incomplete download'));
    expect(task.received, 500);
    expect(finished, isFalse);
    // No finished file and no leftover .part temp file.
    expect(dir.listSync(recursive: true).whereType<File>(), isEmpty);
  });
}

/// Minimal provider with one downloadable track, for the download tests.
class _FakeProvider extends SourceProvider {
  @override
  String get id => 'fake';
  @override
  String get name => 'Fake';
  @override
  String get tagline => 'Test provider';
  @override
  IconData get icon => const IconData(0xe000);
  @override
  Color get brandColor => const Color(0xFF000000);
  @override
  String get licenseNote => 'Tests only.';
  @override
  Future<List<FeedSection>> browse() async => const [];
  @override
  Future<List<Track>> search(String query) async => const [];
  @override
  Future<StreamInfo> resolveStream(Track track, {bool video = false}) async => const StreamInfo('https://example.test/x.mp3');
  @override
  DownloadCapability downloadCapability(Track track) => DownloadCapability.allowed;
  @override
  Future<StreamInfo?> resolveDownload(Track track) async => const StreamInfo('https://example.test/x.mp3', mime: 'audio/mpeg');
}
