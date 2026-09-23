/// Languages the app should surface first in every language picker, and
/// what's known about whether they're realistically available at all.
///
/// This app has no server and no paid API — every STT/TTS language comes
/// from whatever engine is already installed on the phone (Google's, or the
/// OEM's). We can't add a language that engine doesn't ship; we can only
/// make the ones it does ship easy to find, and be honest about the ones it
/// doesn't.
class PriorityLanguage {
  final String bcp47Prefix;
  final String displayName;

  const PriorityLanguage(this.bcp47Prefix, this.displayName);
}

/// Ordered highest-priority-first. Somali is included because some Android
/// TTS engine versions do ship it, even though on-device speech
/// *recognition* support for it is inconsistent — let it show up when the
/// device has it rather than hiding it.
const List<PriorityLanguage> priorityLanguages = [
  PriorityLanguage('ar', 'Arabic'),
  PriorityLanguage('sw', 'Swahili'),
  PriorityLanguage('so', 'Somali'),
];

/// Maasai (Maa) has no ISO 639-1 code and, as far as could be verified, no
/// commercial STT/TTS engine (Google, Samsung, or otherwise) supports it at
/// any price — not a gap this app's architecture can close. Kept as its own
/// constant so callers can show an explicit "not available anywhere" note
/// instead of implying it's just missing from this one device.
const String unsupportedMaasaiNote =
    'Maasai isn\'t available: no speech engine on the market currently supports it.';

String _codeOf(String bcp47Tag) => bcp47Tag.split(RegExp('[-_]')).first.toLowerCase();

/// Sorts [tags] so any priority language present comes first, in priority
/// order, followed by everything else in its original relative order.
List<String> sortByPriority(List<String> tags) {
  final byCode = <String, List<String>>{};
  final rest = <String>[];
  for (final tag in tags) {
    final code = _codeOf(tag);
    final isPriority = priorityLanguages.any((p) => p.bcp47Prefix == code);
    if (isPriority) {
      byCode.putIfAbsent(code, () => []).add(tag);
    } else {
      rest.add(tag);
    }
  }
  return [
    for (final p in priorityLanguages) ...?byCode[p.bcp47Prefix],
    ...rest,
  ];
}

/// Same as [sortByPriority] but for any list where the BCP-47 tag has to be
/// extracted with [codeOf] (e.g. a list of locale objects rather than bare
/// strings).
List<T> sortByPriorityWith<T>(List<T> items, String Function(T) codeOf) {
  final byCode = <String, List<T>>{};
  final rest = <T>[];
  for (final item in items) {
    final code = _codeOf(codeOf(item));
    final isPriority = priorityLanguages.any((p) => p.bcp47Prefix == code);
    if (isPriority) {
      byCode.putIfAbsent(code, () => []).add(item);
    } else {
      rest.add(item);
    }
  }
  return [
    for (final p in priorityLanguages) ...?byCode[p.bcp47Prefix],
    ...rest,
  ];
}

/// Which of [priorityLanguages] are NOT present in [availableTags] — i.e.
/// what to tell the user this device's installed speech engine can't do.
List<PriorityLanguage> missingPriorityLanguages(List<String> availableTags) {
  final availableCodes = availableTags.map(_codeOf).toSet();
  return [
    for (final p in priorityLanguages)
      if (!availableCodes.contains(p.bcp47Prefix)) p,
  ];
}
