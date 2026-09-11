/// Converts a tafsir source's raw HTML-ish `content` string (QUL exports
/// tafsir text with presentational tags/classes, e.g. `<div class=ar
/// lang=ar><p>...</p></div>` or `<span class="arabic qpc-hafs">...</span>`
/// — verified directly against all 3 downloaded sources) into plain text
/// suitable for a normal `Text` widget.
///
/// This is a **display-only** transform. `tafsir_entries.content` itself is
/// stored byte-for-byte from the source (tool/ingest_quran_data.dart never
/// touches it) — nothing here writes back to the database. It's also not
/// Quran source text (CLAUDE.md rule #1 doesn't apply to tafsir commentary
/// text), but the same "never mutate stored data" discipline is kept
/// anyway: this only ever runs on a copy at render time.
///
/// This project has no HTML-rendering dependency (keeping the dependency
/// set small, matching the rest of pubspec.yaml), so structure is kept only
/// as plain-text line breaks (paragraphs/`<br>` -> newline) rather than
/// rendering bold/color spans.
String stripTafsirHtml(String html) {
  String s = html;
  // Block-level boundaries -> newlines, before tags are stripped entirely.
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  s = s.replaceAll(
    RegExp(r'</(p|div)\s*>', caseSensitive: false),
    '\n\n',
  );
  // Strip every remaining tag (opening/closing/self-closing).
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  // Decode the handful of HTML entities actually present in these sources.
  const entities = {
    '&nbsp;': ' ',
    '&amp;': '&',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&lt;': '<',
    '&gt;': '>',
  };
  entities.forEach((entity, replacement) {
    s = s.replaceAll(entity, replacement);
  });
  // Collapse runs of blank lines and trim trailing/leading whitespace per
  // line, without touching the actual wording.
  s = s
      .split('\n')
      .map((line) => line.trim())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  return s;
}
