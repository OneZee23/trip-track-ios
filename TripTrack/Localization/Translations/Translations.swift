import Foundation

/// The five languages added in 0.6.1: German, Spanish, French, Italian, Polish.
///
/// Russian and English are NOT here — they stay written inline in `AppStrings`,
/// where the doc comment that explains a piece of copy sits right next to it.
/// Everything else is a table keyed by the `AppStrings` function name, because
/// seven inline branches per string would have made those doc comments
/// unreadable and the file three times longer.
///
/// `AppStrings.tr` reads these; a missing key falls back to English rather than
/// showing the raw key. `TranslationsCoverageTests` fails if a key here has no
/// matching function, or if a function has no key here — that test is the only
/// thing standing between a renamed function and a silently English screen.
enum Translations {}
