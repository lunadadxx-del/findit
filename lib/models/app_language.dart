/// Supported languages in FindIt.
enum AppLanguage {
  english('en', 'en-US', 'English', 'English'),
  hindi('hi', 'hi-IN', 'Hindi', 'हिंदी'),
  kannada('kn', 'kn-IN', 'Kannada', 'ಕನ್ನಡ'),
  telugu('te', 'te-IN', 'Telugu', 'తెలుగు'),
  tamil('ta', 'ta-IN', 'Tamil', 'தமிழ்');

  final String code;
  final String locale;
  final String englishName;
  final String nativeName;

  const AppLanguage(this.code, this.locale, this.englishName, this.nativeName);

  static AppLanguage fromCode(String? code) {
    if (code == null) return AppLanguage.english;
    for (final l in AppLanguage.values) {
      if (l.code.toLowerCase() == code.toLowerCase() ||
          l.locale.toLowerCase() == code.toLowerCase()) {
        return l;
      }
    }
    return AppLanguage.english;
  }
}
