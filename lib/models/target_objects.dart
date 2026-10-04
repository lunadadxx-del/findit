/// The objects FindIt can actually detect.
///
/// These are the COCO labels our bundled SSD MobileNet model was trained on.
/// The map keys are the friendly names users say ("phone"); the values are
/// the exact model labels ("cell phone").
///
/// Deliberately small and honest: keys and wallet are NOT in the COCO label
/// set, so they are listed in [unsupportedTargets] and the app must say so
/// instead of pretending to detect them.
class TargetObjects {
  static const Map<String, String> supported = {
    'bottle': 'bottle',
    'cup': 'cup',
    'book': 'book',
    'phone': 'cell phone',
    'backpack': 'backpack',
    'bag': 'handbag',
    'remote': 'remote',
    'keyboard': 'keyboard',
    'mouse': 'mouse',
  };

  /// Requested often, but not detectable by the current model.
  /// The UI must present these honestly ("not supported yet").
  static const List<String> unsupported = ['keys', 'wallet', 'spectacles'];

  static bool isSupported(String friendlyName) =>
      supported.containsKey(friendlyName.toLowerCase());

  static String? modelLabelFor(String friendlyName) =>
      supported[friendlyName.toLowerCase()];

  /// Tries to map free-form voice input ("find my bottle please") to a
  /// supported friendly name. Returns null when nothing matches.
  static String? matchVoiceInput(String transcript) {
    final lower = transcript.toLowerCase();
    for (final name in supported.keys) {
      if (lower.contains(name)) return name;
    }
    // Common phrasings.
    if (lower.contains('mobile') || lower.contains('cell')) return 'phone';
    if (lower.contains('handbag') || lower.contains('purse')) return 'bag';
    if (lower.contains('laptop')) return null; // not in our list; be honest
    return null;
  }
}
