import 'dart:ui' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:nokbox/audio/autoeq.dart';
import 'package:nokbox/audio/eq.dart';
import 'package:nokbox/audio/mpv_filters.dart';
import 'package:nokbox/audio/queue.dart';
import 'package:nokbox/core/theme/nok_theme.dart';
import 'package:nokbox/data/database.dart';
import 'package:nokbox/data/models.dart';
import 'package:nokbox/library/text_utils.dart';
import 'package:nokbox/lyrics/lrc.dart';
import 'package:nokbox/sources/providers/custom_provider.dart';
import 'package:nokbox/sources/source_matcher.dart';
import 'package:nokbox/sources/youtube/sponsorblock.dart';

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
}
