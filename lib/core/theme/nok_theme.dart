import 'dart:convert';

import 'package:material_ui/material_ui.dart';

/// A user-editable NOKBOX theme. Serializable for save / import / export.
class NokThemeSpec {
  const NokThemeSpec({
    required this.name,
    required this.accent,
    required this.background,
    required this.surface,
    this.secondary,
    this.amoled = true,
    this.dynamicFromArt = false,
    this.radius = 18,
    this.brightness = Brightness.dark,
  });

  final String name;
  final Color accent;
  final Color background;
  final Color surface;
  final Color? secondary;
  final bool amoled;
  final bool dynamicFromArt;
  final double radius;
  final Brightness brightness;

  static const nokRed = Color(0xFFE5121B);

  /// Stock theme: OLED pure black + red, matching the app icon.
  static const stock = NokThemeSpec(
    name: 'NOKBOX OLED',
    accent: nokRed,
    background: Color(0xFF000000),
    surface: Color(0xFF0E0E0E),
    secondary: Color(0xFFFF4D4D),
  );

  static const presets = <NokThemeSpec>[
    stock,
    NokThemeSpec(name: 'Blood Moon', accent: Color(0xFFB0000B), background: Color(0xFF000000), surface: Color(0xFF140405), secondary: Color(0xFFFF2E3A)),
    NokThemeSpec(name: 'Cherry Drip', accent: Color(0xFFFF1F4B), background: Color(0xFF050003), surface: Color(0xFF16070C), secondary: Color(0xFFFF7A9A)),
    NokThemeSpec(name: 'Gold Grillz', accent: Color(0xFFFFC107), background: Color(0xFF000000), surface: Color(0xFF121006), secondary: Color(0xFFFFE082)),
    NokThemeSpec(name: 'Purple Lean', accent: Color(0xFFA020F0), background: Color(0xFF000000), surface: Color(0xFF100818), secondary: Color(0xFFD291FF)),
    NokThemeSpec(name: 'Ice Chain', accent: Color(0xFF29D3FF), background: Color(0xFF000000), surface: Color(0xFF061218), secondary: Color(0xFFA6F0FF)),
    NokThemeSpec(name: 'Money Green', accent: Color(0xFF1DE97A), background: Color(0xFF000000), surface: Color(0xFF06140C), secondary: Color(0xFF9CFFC8)),
    NokThemeSpec(name: 'Sunset Blvd', accent: Color(0xFFFF6A00), background: Color(0xFF0A0402), surface: Color(0xFF1A0D06), secondary: Color(0xFFFFB37A)),
    NokThemeSpec(name: 'Concrete', accent: Color(0xFFE5121B), background: Color(0xFF15161A), surface: Color(0xFF202228), secondary: Color(0xFFB0B3BA), amoled: false),
    NokThemeSpec(name: 'Daylight', accent: Color(0xFFD10F18), background: Color(0xFFF6F6F6), surface: Color(0xFFFFFFFF), secondary: Color(0xFF4A4A4A), amoled: false, brightness: Brightness.light),
  ];

  NokThemeSpec copyWith({
    String? name,
    Color? accent,
    Color? background,
    Color? surface,
    Color? secondary,
    bool? amoled,
    bool? dynamicFromArt,
    double? radius,
    Brightness? brightness,
  }) =>
      NokThemeSpec(
        name: name ?? this.name,
        accent: accent ?? this.accent,
        background: background ?? this.background,
        surface: surface ?? this.surface,
        secondary: secondary ?? this.secondary,
        amoled: amoled ?? this.amoled,
        dynamicFromArt: dynamicFromArt ?? this.dynamicFromArt,
        radius: radius ?? this.radius,
        brightness: brightness ?? this.brightness,
      );

  Map<String, dynamic> toJson() => {
        'format': 'nokbox-theme',
        'version': 1,
        'name': name,
        'accent': colorToHex(accent),
        'background': colorToHex(background),
        'surface': colorToHex(surface),
        if (secondary != null) 'secondary': colorToHex(secondary!),
        'amoled': amoled,
        'dynamicFromArt': dynamicFromArt,
        'radius': radius,
        'brightness': brightness.name,
      };

  factory NokThemeSpec.fromJson(Map<String, dynamic> j) => NokThemeSpec(
        name: j['name'] as String? ?? 'Imported',
        accent: hexToColor(j['accent'] as String?) ?? nokRed,
        background: hexToColor(j['background'] as String?) ?? Colors.black,
        surface: hexToColor(j['surface'] as String?) ?? const Color(0xFF0E0E0E),
        secondary: hexToColor(j['secondary'] as String?),
        amoled: j['amoled'] as bool? ?? true,
        dynamicFromArt: j['dynamicFromArt'] as bool? ?? false,
        radius: (j['radius'] as num?)?.toDouble() ?? 18,
        brightness: j['brightness'] == 'light' ? Brightness.light : Brightness.dark,
      );

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}

String colorToHex(Color c, {bool withAlpha = true}) {
  final v = c.toARGB32();
  final s = v.toRadixString(16).padLeft(8, '0').toUpperCase();
  return '#${withAlpha ? s : s.substring(2)}';
}

Color? hexToColor(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceAll('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

/// Builds the Material theme from a spec and optional album-art accent.
ThemeData buildNokTheme(NokThemeSpec spec, {Color? dynamicAccent}) {
  final accent = (spec.dynamicFromArt && dynamicAccent != null) ? dynamicAccent : spec.accent;
  final dark = spec.brightness == Brightness.dark;
  final bg = dark && spec.amoled ? Colors.black : spec.background;
  final surface = dark && spec.amoled ? Color.alphaBlend(accent.withValues(alpha: 0.05), const Color(0xFF0A0A0A)) : spec.surface;
  final onBg = dark ? Colors.white : const Color(0xFF111111);
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: spec.brightness,
  ).copyWith(
    primary: accent,
    onPrimary: accent.computeLuminance() > 0.5 ? Colors.black : Colors.white,
    secondary: spec.secondary ?? accent,
    surface: bg,
    onSurface: onBg,
    surfaceContainerLowest: bg,
    surfaceContainerLow: Color.alphaBlend(onBg.withValues(alpha: 0.03), surface),
    surfaceContainer: Color.alphaBlend(onBg.withValues(alpha: 0.05), surface),
    surfaceContainerHigh: Color.alphaBlend(onBg.withValues(alpha: 0.08), surface),
    surfaceContainerHighest: Color.alphaBlend(onBg.withValues(alpha: 0.12), surface),
    outlineVariant: onBg.withValues(alpha: 0.10),
  );
  final r = BorderRadius.circular(spec.radius);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: spec.brightness,
    scaffoldBackgroundColor: bg,
    canvasColor: bg,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: onBg, displayColor: onBg).copyWith(
          headlineLarge: base.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.5, color: onBg),
          headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.5, color: onBg),
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: onBg),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: onBg),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: onBg, letterSpacing: 0.5),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: r),
      margin: EdgeInsets.zero,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Color.alphaBlend(accent.withValues(alpha: 0.04), bg),
      indicatorColor: accent.withValues(alpha: 0.22),
      height: 66,
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: onBg)),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? accent : onBg.withValues(alpha: 0.7))),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: accent,
      inactiveTrackColor: accent.withValues(alpha: 0.18),
      thumbColor: accent,
      overlayColor: accent.withValues(alpha: 0.12),
      trackHeight: 4,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: accent,
      unselectedLabelColor: onBg.withValues(alpha: 0.6),
      indicatorColor: accent,
      dividerColor: Colors.transparent,
      labelStyle: const TextStyle(fontWeight: FontWeight.w800),
      tabAlignment: TabAlignment.start,
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
      side: BorderSide(color: onBg.withValues(alpha: 0.12)),
    ),
    listTileTheme: ListTileThemeData(iconColor: onBg.withValues(alpha: 0.8)),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(spec.radius + 6))),
      showDragHandle: true,
    ),
    dialogTheme: DialogThemeData(backgroundColor: scheme.surfaceContainerHigh, shape: RoundedRectangleBorder(borderRadius: r)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      border: OutlineInputBorder(borderRadius: r, borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    dividerTheme: DividerThemeData(color: onBg.withValues(alpha: 0.08), space: 1),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: scheme.surfaceContainerHighest, contentTextStyle: TextStyle(color: onBg)),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : null),
    ),
  );
}
