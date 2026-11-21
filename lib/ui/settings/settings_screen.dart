import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_cookie_manager_plus/webview_cookie_manager_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/diagnostics.dart';
import '../../app_globals.dart';

import '../../core/settings.dart';
import '../../library/library_controller.dart';
import '../../library/text_utils.dart';
import '../../sources/download_manager.dart';
import '../../sources/source_registry.dart';
import '../../sources/youtube/sponsorblock.dart';
import '../widgets/common.dart';
import 'appearance_screen.dart';
import 'equalizer_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reg = context.watch<SourceRegistry>();
    final cs = Theme.of(context).colorScheme;
    Widget tile(IconData i, String t, String sub, Widget Function() page) => ListTile(
          leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)), child: Icon(i, color: cs.primary)),
          title: Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page())),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: const NokWordmark(size: 30, tagline: true)),
        tile(Icons.palette_rounded, 'Theme & appearance', 'OLED black + red, HSV color wheel, presets, import/export', () => const AppearanceScreen()),
        tile(Icons.equalizer_rounded, 'Equalizer', 'Graphic + parametric, AutoEQ, bass boost — local & streams', () => const EqualizerScreen()),
        tile(Icons.play_circle_rounded, 'Playback', 'Gapless, ReplayGain, fades, resume, loudness', () => const PlaybackSettings()),
        tile(Icons.dynamic_feed_rounded, 'Sources & feed', 'Feed: ${reg.feedProvider.name} · keys, auto source switching', () => const SourcesSettings()),
        tile(Icons.smart_display_rounded, 'YouTube extras', 'SponsorBlock, Return YouTube Dislike, ad-free streams', () => const YoutubeSettings()),
        tile(Icons.library_music_rounded, 'Library & indexing', 'Folders, excludes, filters, separators', () => const LibrarySettings()),
        tile(Icons.lyrics_rounded, 'Lyrics', 'LRCLIB synced lyrics, offline cache', () => const LyricsSettings()),
        tile(Icons.download_rounded, 'Downloads', 'Only where the source allows it', () => const DownloadsScreen()),
        tile(Icons.backup_rounded, 'Backup & restore', 'Documented, mergeable JSON', () => const BackupSettings()),
        tile(Icons.account_circle_rounded, 'YouTube account', 'Sign in for your own recommendations', () => const YoutubeAccountScreen()),
        tile(Icons.bug_report_rounded, 'Diagnostics', 'Export a report when something goes wrong', () => const DiagnosticsScreen()),
        tile(Icons.info_rounded, 'About & licenses', 'Credits, open-source notices', () => const AboutScreen()),
        const SizedBox(height: 30),
      ]),
    );
  }
}

class PlaybackSettings extends StatelessWidget {
  const PlaybackSettings({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    Future<void> setAndApply(String k, Object v) async {
      await s.set(k, v);
      await nok.playback.applyEngineSettings();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Playback')),
      body: ListView(children: [
        SwitchListTile(title: const Text('Gapless playback'), subtitle: const Text('Pre-buffers the next track'), value: s.gapless, onChanged: (v) => setAndApply('gapless', v)),
        ListTile(
          title: const Text('ReplayGain'),
          trailing: SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'no', label: Text('Off')), ButtonSegment(value: 'track', label: Text('Track')), ButtonSegment(value: 'album', label: Text('Album'))],
            selected: {s.replayGain},
            onSelectionChanged: (v) => setAndApply('replayGain', v.first),
          ),
        ),
        ListTile(
          title: const Text('Loudness boost'),
          subtitle: Slider(value: s.loudnessBoostDb, min: 0, max: 6, divisions: 12, label: '+${s.loudnessBoostDb} dB', onChanged: (v) => setAndApply('loudnessBoostDb', v)),
          trailing: Text('+${s.loudnessBoostDb.toStringAsFixed(1)} dB'),
        ),
        SwitchListTile(title: const Text('Fade on play / pause'), subtitle: const Text('No volume spikes on resume'), value: s.fadeOnPause, onChanged: (v) => s.set('fadeOnPause', v)),
        ListTile(title: const Text('Fade length'), subtitle: Slider(value: s.fadeMs.toDouble(), min: 0, max: 1000, divisions: 20, onChanged: (v) => s.set('fadeMs', v.round())), trailing: Text('${s.fadeMs} ms')),
        SwitchListTile(title: const Text('Remember position in long tracks'), subtitle: Text('Mixtapes, podcasts, sets ≥ ${s.resumeMinMinutes} min'), value: s.resumeTracks, onChanged: (v) => s.set('resumeTracks', v)),
        ListTile(title: const Text('Count as played after'), subtitle: Slider(value: s.minListenSecondsForHistory.toDouble(), min: 5, max: 120, divisions: 23, onChanged: (v) => s.set('minListenSec', v.round())), trailing: Text('${s.minListenSecondsForHistory}s')),
        const ListTile(title: Text('Crossfade & smart fades'), subtitle: Text('Coming in v1'), enabled: false),
      ]),
    );
  }
}

class SourcesSettings extends StatelessWidget {
  const SourcesSettings({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final reg = context.watch<SourceRegistry>();
    Widget keyField(String label, String key, {bool secret = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: TextFormField(
            initialValue: s.get(key, ''),
            obscureText: secret,
            decoration: InputDecoration(labelText: label),
            onFieldSubmitted: (v) => s.set(key, v.trim()),
            onChanged: (v) => s.set(key, v.trim()),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Sources & feed')),
      body: ListView(children: [
        const SectionHeader('Feed source', subtitle: 'Type any service or URL. Empty = YouTube.'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextFormField(
            initialValue: s.sourceField,
            decoration: InputDecoration(hintText: 'YouTube (default)', prefixIcon: Icon(reg.feedProvider.icon), helperText: 'Now: ${reg.feedProvider.name} — ${reg.feedProvider.tagline}'),
            onFieldSubmitted: (v) => s.sourceField = v,
          ),
        ),
        SwitchListTile(title: const Text('Auto source switching'), subtitle: const Text('If a stream fails: your library → download-friendly sources → other legal streams'), value: s.autoSourceSwitch, onChanged: (v) => s.autoSourceSwitch = v),
        SwitchListTile(title: const Text('Data saver'), subtitle: const Text('Lower stream quality on cellular'), value: s.dataSaver, onChanged: (v) => s.set('dataSaver', v)),
        const SectionHeader('Providers'),
        for (final p in reg.builtIns)
          ExpansionTile(
            leading: Icon(p.icon, color: p.brandColor),
            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(p.setupHint == null ? p.tagline : 'Needs setup'),
            children: [
              if (p.licenseNote.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(p.licenseNote, style: const TextStyle(fontSize: 12))),
              if (p.id == 'podcast') ...[keyField('Podcast Index key (optional)', 'podcastIndexKey'), keyField('Podcast Index secret', 'podcastIndexSecret', secret: true)],
              if (p.id == 'youtube')
                SwitchListTile(
                  title: const Text('Download as video'),
                  subtitle: const Text('Off: high-quality audio (m4a). On: video (mp4).'),
                  value: s.youtubeDownloadVideo,
                  onChanged: (v) => s.set('ytDownloadVideo', v),
                ),
            ],
          ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Not integrated: SoundCloud (terms forbid 3rd-party downloads/mixing), Tidal & Deezer (DRM). NOKBOX never bypasses DRM or paywalls.', style: TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }
}

class YoutubeSettings extends StatelessWidget {
  const YoutubeSettings({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final sb = context.watch<SponsorBlockController>();
    return Scaffold(
      appBar: AppBar(title: const Text('YouTube extras')),
      body: ListView(children: [
        const ListTile(
          leading: Icon(Icons.block_rounded),
          title: Text('Ad-free by design'),
          subtitle: Text('NOKBOX plays the direct media stream, so YouTube\'s ad requests are never made or played.'),
        ),
        SwitchListTile(title: const Text('SponsorBlock'), subtitle: const Text('Community-submitted segments (sponsor.ajay.app). Only a 4-char hash prefix of the video id is sent.'), value: sb.enabled, onChanged: (v) => s.set('sb.enabled', v)),
        if (sb.enabled)
          for (final c in sbCategories)
            ListTile(
              leading: CircleAvatar(radius: 7, backgroundColor: c.color),
              title: Text(c.label),
              trailing: DropdownButton<SbAction>(
                value: sb.actionFor(c.id),
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: SbAction.skip, child: Text('Skip')),
                  DropdownMenuItem(value: SbAction.mute, child: Text('Mute')),
                  DropdownMenuItem(value: SbAction.show, child: Text('Show on bar')),
                  DropdownMenuItem(value: SbAction.off, child: Text('Off')),
                ],
                onChanged: (a) => sb.setAction(c.id, a!),
              ),
            ),
        SwitchListTile(title: const Text('Return YouTube Dislike'), subtitle: const Text('Show estimated dislikes (returnyoutubedislike.com)'), value: s.get('ryd.enabled', true), onChanged: (v) => s.set('ryd.enabled', v)),
      ]),
    );
  }
}

class LibrarySettings extends StatelessWidget {
  const LibrarySettings({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final lib = context.watch<LibraryController>();
    Future<void> addFolder(String key) async {
      final d = await FilePicker.getDirectoryPath();
      if (d == null) return;
      await s.set(key, {...s.get<List<String>>(key, <String>[]), d}.toList());
      lib.startWatching();
      lib.rescan();
    }

    Widget folderList(String title, String key) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionHeader(title, action: 'Add', onAction: () => addFolder(key)),
          for (final f in s.get<List<String>>(key, <String>[]))
            ListTile(dense: true, leading: const Icon(Icons.folder_rounded), title: Text(f, maxLines: 1, overflow: TextOverflow.ellipsis), trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => s.set(key, s.get<List<String>>(key, <String>[]).where((e) => e != f).toList()))),
        ]);
    return Scaffold(
      appBar: AppBar(title: const Text('Library & indexing')),
      body: ListView(children: [
        ListTile(leading: const Icon(Icons.phone_iphone_rounded), title: const Text('NOKBOX folder (always indexed & watched)'), subtitle: Text(lib.documentsDir, maxLines: 2)),
        if (lib.lastScanSummary != null) ListTile(leading: const Icon(Icons.check_circle_rounded), title: const Text('Last scan'), subtitle: Text(lib.lastScanSummary!)),
        folderList('Extra library folders', 'libraryFolders'),
        folderList('Watch folders', 'watchFolders'),
        folderList('Excluded folders', 'excludedFolders'),
        ListTile(title: const Text('Minimum duration'), subtitle: Slider(value: s.minDurationSec.toDouble(), max: 180, divisions: 36, onChanged: (v) => s.set('minDurationSec', v.round())), trailing: Text('${s.minDurationSec}s')),
        ListTile(title: const Text('Minimum file size'), subtitle: Slider(value: s.minSizeKb.toDouble(), max: 2048, divisions: 32, onChanged: (v) => s.set('minSizeKb', v.round())), trailing: Text('${s.minSizeKb} KB')),
        SwitchListTile(title: const Text('Filter duplicates'), subtitle: const Text('Keeps the best quality copy'), value: s.filterDuplicates, onChanged: (v) => s.set('filterDuplicates', v)),
        SwitchListTile(title: const Text('Extract feat. artists'), value: s.extractFeat, onChanged: (v) => s.set('extractFeat', v)),
        SwitchListTile(title: const Text('Index videos'), value: s.includeVideos, onChanged: (v) => s.set('includeVideos', v)),
        ListTile(
          title: const Text('Artist separators'),
          subtitle: Text(s.artistSeparators.map((e) => '"$e"').join('  ')),
          trailing: const Icon(Icons.edit_rounded),
          onTap: () async {
            final v = await promptText(context, title: 'Artist separators (one per line)', initial: s.artistSeparators.join('\n'));
            if (v != null) s.set('artistSeparators', v.split('\n').where((e) => e.isNotEmpty).toList());
          },
        ),
        ListTile(
          leading: const Icon(Icons.refresh_rounded),
          title: const Text('Rescan now'),
          onTap: () async {
            await lib.rescan();
            if (context.mounted) snack(context, lib.lastScanSummary ?? 'Done');
          },
        ),
      ]),
    );
  }
}

class LyricsSettings extends StatelessWidget {
  const LyricsSettings({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('Lyrics')),
      body: ListView(children: [
        SwitchListTile(title: const Text('Fetch lyrics automatically'), subtitle: const Text('From LRCLIB (free & open)'), value: s.lyricsAutoFetch, onChanged: (v) => s.set('lyricsAutoFetch', v)),
        SwitchListTile(title: const Text('Save .lrc next to local files'), value: s.lyricsSaveLrc, onChanged: (v) => s.set('lyricsSaveLrc', v)),
        ListTile(title: const Text('Lyrics text size'), subtitle: Slider(value: s.lyricsFontScale, min: 0.7, max: 1.6, onChanged: (v) => s.set('lyricsFontScale', v))),
        ListTile(title: const Text('Offline cache'), subtitle: Text('${nok.db.lyricsCacheCount()} songs cached'), trailing: TextButton(onPressed: () => nok.db.clearLyricsCache(), child: const Text('Clear'))),
        const Padding(padding: EdgeInsets.all(16), child: Text('Lyrics are copyrighted by their owners and shown for personal listening only.', style: TextStyle(fontSize: 12))),
      ]),
    );
  }
}

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final dm = context.watch<DownloadManager>();
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads'), actions: [TextButton(onPressed: dm.clearFinished, child: const Text('Clear done'))]),
      body: dm.tasks.isEmpty
          ? const EmptyState(icon: Icons.download_rounded, title: 'No downloads', message: 'Tap the download icon on any song or video. Finished downloads land in your Library.')
          : ListView(children: [
              for (final t in dm.tasks.reversed)
                ListTile(
                  leading: Artwork(uri: t.track.artUri, size: 46),
                  title: Text(t.track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${t.status.name}${t.total > 0 ? ' · ${formatBytes(t.received)} / ${formatBytes(t.total)}' : ''}${t.error != null ? ' · ${t.error}' : ''}', maxLines: 2),
                    if (t.status == DownloadStatus.running) LinearProgressIndicator(value: t.total > 0 ? t.progress : null),
                  ]),
                  trailing: switch (t.status) {
                    DownloadStatus.running || DownloadStatus.queued => IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => dm.cancel(t)),
                    DownloadStatus.failed => IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => dm.retry(t)),
                    _ => const Icon(Icons.check_rounded),
                  },
                ),
            ]),
    );
  }
}

class BackupSettings extends StatelessWidget {
  const BackupSettings({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: ListView(children: [
        ListTile(
          leading: const Icon(Icons.ios_share_rounded),
          title: const Text('Export backup'),
          subtitle: const Text('Settings, themes, EQ, playlists, favorites, history, queues'),
          onTap: () async {
            final json = nok.backup.export();
            await SharePlus.instance.share(ShareParams(text: json, subject: 'NOKBOX backup'));
          },
        ),
        ListTile(
          leading: const Icon(Icons.copy_rounded),
          title: const Text('Copy backup to clipboard'),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: nok.backup.export()));
            if (context.mounted) snack(context, 'Backup copied');
          },
        ),
        ListTile(
          leading: const Icon(Icons.restore_rounded),
          title: const Text('Restore from file (merge)'),
          onTap: () async {
            final f = (await FilePicker.pickFiles()).firstOrNull;
            if (f == null) return;
            final text = await f.xFile.readAsString();
            try {
              final msg = await nok.backup.restore(text);
              nok.library.loadFromDb();
              if (context.mounted) snack(context, msg);
            } catch (e) {
              if (context.mounted) snack(context, 'Restore failed: $e');
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.content_paste_rounded),
          title: const Text('Restore from clipboard (merge)'),
          onTap: () async {
            final d = await Clipboard.getData('text/plain');
            try {
              final msg = await nok.backup.restore(d?.text ?? '');
              nok.library.loadFromDb();
              if (context.mounted) snack(context, msg);
            } catch (e) {
              if (context.mounted) snack(context, 'Restore failed: $e');
            }
          },
        ),
      ]),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ClipRRect(borderRadius: BorderRadius.circular(24), child: Image.asset('assets/branding/icon_source.jpg', height: 220, fit: BoxFit.cover)),
        const SizedBox(height: 14),
        const NokWordmark(size: 34, tagline: true),
        const SizedBox(height: 8),
        const Text('Version 0.2.1'),
        const SectionHeader('Credits', padding: EdgeInsets.fromLTRB(0, 20, 0, 8)),
        const Text('• LRCLIB — open synced lyrics (lrclib.net)\n'
            '• AutoEQ — headphone EQ by Jaakko Pasanen (MIT); measurements by oratory1990, Rtings, Innerfidelity & others\n'
            '• SponsorBlock — segment data by Ajay Ramachandran & contributors (CC BY-NC-SA 4.0)\n'
            '• Return YouTube Dislike — dislike estimates (returnyoutubedislike.com)\n'
            '• Radio Browser, Podcast Index, iTunes Search, Internet Archive\n'
            '• media_kit / libmpv / FFmpeg (audio & video engine)'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => showLicensePage(context: context, applicationName: 'NOKBOX', applicationLegalese: 'A MUZIK JUNKIE PARADISE'),
          icon: const Icon(Icons.description_rounded),
          label: const Text('Open-source licenses'),
        ),
      ]),
    );
  }
}

class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: ValueListenableBuilder<int>(
        valueListenable: Diag.changes,
        builder: (context, _, __) {
          final reports = Diag.reports();
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(Diag.flagged || reports.isNotEmpty ? '${reports.length} problem report(s) saved.' : 'No problems recorded. The log clears itself while everything works.'),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Export diagnostic'),
              onPressed: () async {
                final f = await Diag.exportBundle();
                await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], subject: 'NOKBOX diagnostics'));
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(icon: const Icon(Icons.delete_sweep_rounded), label: const Text('Clear reports'), onPressed: Diag.clear),
            for (final r in reports) ListTile(dense: true, leading: const Icon(Icons.description_outlined), title: Text(r.uri.pathSegments.last)),
          ]);
        },
      ),
    );
  }
}

class YoutubeAccountScreen extends StatelessWidget {
  const YoutubeAccountScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final acc = nok.ytAccount;
    return ListenableBuilder(
      listenable: acc,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('YouTube account')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          ListTile(
            leading: CircleAvatar(backgroundImage: acc.avatar != null ? NetworkImage(acc.avatar!) : null, child: acc.avatar == null ? const Icon(Icons.person_rounded) : null),
            title: Text(acc.signedIn ? (acc.name ?? 'Signed in') : 'Not signed in'),
            subtitle: Text(acc.signedIn ? 'Home shows your YouTube recommendations and subscriptions' : 'Home shows trending + picks based on what you play'),
          ),
          const SizedBox(height: 12),
          if (!acc.signedIn)
            FilledButton.icon(
              icon: const Icon(Icons.login_rounded),
              label: const Text('Sign in to YouTube'),
              onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const _YoutubeLogin())),
            )
          else
            OutlinedButton.icon(
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
              onPressed: () async {
                await acc.signOut();
                try {
                  await WebviewCookieManager().clearCookies();
                } catch (_) {}
              },
            ),
        ]),
      ),
    );
  }
}

class _YoutubeLogin extends StatefulWidget {
  const _YoutubeLogin();
  @override
  State<_YoutubeLogin> createState() => _YoutubeLoginState();
}

class _YoutubeLoginState extends State<_YoutubeLogin> {
  late final WebViewController _c;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1')
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: _check))
      ..loadRequest(Uri.parse('https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fwww.youtube.com%2F'));
  }

  Future<void> _check(String url) async {
    if (_done || !Uri.parse(url).host.endsWith('youtube.com')) return;
    try {
      final cookies = await WebviewCookieManager().getCookies('https://www.youtube.com');
      final header = cookies.map((c) => '${c.name}=${c.value}').join('; ');
      if (!header.contains('SAPISID=')) return;
      _done = true;
      await nok.ytAccount.save(header);
      await nok.ytAccount.refreshProfile();
      Diag.info('yt.account', 'signed in');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      Diag.error('yt.account', 'cookie read failed', error: e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Sign in to YouTube')), body: WebViewWidget(controller: _c));
}
