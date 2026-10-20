import 'package:flutter/material.dart';

/// Design tokens. Every colour, size and type style in the app comes from
/// here so the visual language stays consistent and is easy to retune.
///
/// Direction: a printed analyst's report rather than a "dashboard".
/// Warm paper, near-black ink, one deep ledger green as the only accent,
/// hairline rules instead of shadows, serif for reading, sans for doing.
abstract final class Palette {
  static const paper = Color(0xFFF6F4EF); // app background
  static const sheet = Color(0xFFFCFBF8); // raised surfaces (cards, panels)
  static const sunken = Color(0xFFEFECE5); // inputs, code, table headers
  static const rule = Color(0xFFE1DDD3); // hairlines
  static const ruleStrong = Color(0xFFC9C3B6);

  static const ink = Color(0xFF1C1B19); // primary text
  static const inkMuted = Color(0xFF5C5952); // secondary text
  static const inkFaint = Color(0xFF8B877E); // captions, placeholders

  static const accent = Color(0xFF1F5C4A); // ledger green
  static const accentHover = Color(0xFF17493A);
  static const accentWash = Color(0xFFE2ECE7);

  static const amber = Color(0xFF8F5B12);
  static const amberWash = Color(0xFFF4EAD7);
  static const brick = Color(0xFF9E3A2B);
  static const brickWash = Color(0xFFF5E3DE);

  /// Chart series, in order. Muted, print-like, distinguishable in greyscale.
  static const series = <Color>[
    Color(0xFF1F5C4A), // green
    Color(0xFFC08A2E), // ochre
    Color(0xFF4A6A8A), // slate
    Color(0xFFB0573A), // terracotta
    Color(0xFF7A6F9B), // dusk
  ];
}

abstract final class Space {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
  static const xxxl = 72.0;
}

abstract final class Radii {
  static const sm = Radius.circular(4);
  static const md = Radius.circular(6);
  static const lg = Radius.circular(10);
}

abstract final class Breakpoints {
  static const compact = 720.0; // below: phone layout, bottom navigation
  static const wide = 1100.0; // above: two-column chart grid
  static const readingWidth = 680.0; // comfortable line length for prose
  static const contentWidth = 1080.0;
}

abstract final class Txt {
  static const _sans = 'Plex Sans';
  static const _serif = 'Plex Serif';
  static const _mono = 'Plex Mono';

  static const tabular = [FontFeature.tabularFigures()];

  /// Chinese glyphs fall back to the bundled Noto Sans SC.
  static const cjk = ['Noto Sans SC'];

  // Serif, for things you read.
  static const display = TextStyle(fontFamily: _serif, fontFamilyFallback: cjk, fontSize: 40, height: 1.12, fontWeight: FontWeight.w400, letterSpacing: -0.6, color: Palette.ink);
  static const title = TextStyle(fontFamily: _serif, fontFamilyFallback: cjk, fontSize: 26, height: 1.2, fontWeight: FontWeight.w400, letterSpacing: -0.3, color: Palette.ink);
  static const heading = TextStyle(fontFamily: _serif, fontFamilyFallback: cjk, fontSize: 19, height: 1.3, fontWeight: FontWeight.w500, color: Palette.ink);
  static const prose = TextStyle(fontFamily: _serif, fontFamilyFallback: cjk, fontSize: 16.5, height: 1.65, fontWeight: FontWeight.w400, color: Palette.ink);
  static const proseLead = TextStyle(fontFamily: _serif, fontFamilyFallback: cjk, fontSize: 19, height: 1.55, fontWeight: FontWeight.w400, color: Palette.ink);

  // Sans, for things you do.
  static const body = TextStyle(fontFamily: _sans, fontFamilyFallback: cjk, fontSize: 14.5, height: 1.5, color: Palette.ink);
  static const bodyMuted = TextStyle(fontFamily: _sans, fontFamilyFallback: cjk, fontSize: 14.5, height: 1.5, color: Palette.inkMuted);
  static const label = TextStyle(fontFamily: _sans, fontFamilyFallback: cjk, fontSize: 13.5, height: 1.3, fontWeight: FontWeight.w500, color: Palette.ink);
  static const caption = TextStyle(fontFamily: _sans, fontFamilyFallback: cjk, fontSize: 12.5, height: 1.4, color: Palette.inkFaint);

  /// Small caps-style section marker ("SUMMARY", "COLUMNS").
  static const eyebrow = TextStyle(fontFamily: _sans, fontFamilyFallback: cjk, fontSize: 11.5, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: 1.1, color: Palette.inkFaint);

  static const figure = TextStyle(fontFamily: _sans, fontFamilyFallback: cjk, fontSize: 28, height: 1.1, fontWeight: FontWeight.w500, color: Palette.ink, fontFeatures: tabular);

  static const mono = TextStyle(fontFamily: _mono, fontFamilyFallback: cjk, fontSize: 13, height: 1.55, color: Palette.ink);
  static const monoSmall = TextStyle(fontFamily: _mono, fontFamilyFallback: cjk, fontSize: 12.5, height: 1.4, color: Palette.ink);
}
