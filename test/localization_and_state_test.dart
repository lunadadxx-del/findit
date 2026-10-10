import 'package:findit/models/app_language.dart';
import 'package:findit/models/detection.dart';
import 'package:findit/models/target_objects.dart';
import 'package:findit/services/guidance_engine.dart';
import 'package:findit/services/localization_service.dart';
import 'package:flutter_test/flutter_test.dart';

Detection _box(
  String label,
  double l,
  double t,
  double r,
  double b, [
  double conf = 0.8,
]) => Detection(
  label: label,
  confidence: conf,
  left: l,
  top: t,
  right: r,
  bottom: b,
);

void main() {
  group('GuidanceState Transitions & Uncertainty', () {
    test(
      'transitions through searching -> detected -> tracking -> guiding -> found',
      () {
        final engine = GuidanceEngine(targetFriendlyName: 'bottle');
        expect(engine.currentState, GuidanceState.searching);

        // Frame 1: candidate detected
        final g1 = engine.guide(_box('bottle', 0.45, 0.4, 0.55, 0.5));
        expect(g1.state, GuidanceState.detected);
        expect(g1.isFound, isFalse);

        // Frame 2: tracked
        final g2 = engine.guide(_box('bottle', 0.45, 0.4, 0.55, 0.5));
        expect(g2.state, GuidanceState.tracking);

        // Frame 3: guiding forward
        final g3 = engine.guide(_box('bottle', 0.45, 0.4, 0.55, 0.5));
        expect(g3.state, GuidanceState.guiding);
        expect(g3.phrase, 'Move forward.');

        // Frame 4: approaching closer
        final g4 = engine.guide(_box('bottle', 0.35, 0.3, 0.65, 0.6));
        expect(g4.state, GuidanceState.closer);
        expect(g4.phrase, "You're getting closer.");

        // Frame 5: near
        final g5 = engine.guide(_box('bottle', 0.30, 0.25, 0.70, 0.65));
        expect(g5.state, GuidanceState.near);
        expect(g5.phrase, 'The object is close.');

        // Frame 6: found (big area and centered)
        final g6 = engine.guide(_box('bottle', 0.25, 0.20, 0.75, 0.80));
        expect(g6.state, GuidanceState.found);
        expect(g6.isFound, isTrue);
        expect(g6.phrase, contains('Stop. bottle found.'));
      },
    );

    test('reacquiring recovery state before entering lost', () {
      final engine = GuidanceEngine(targetFriendlyName: 'bottle');

      // Establish tracking
      engine.guide(_box('bottle', 0.45, 0.4, 0.55, 0.5));
      engine.guide(_box('bottle', 0.45, 0.4, 0.55, 0.5));
      final gTracked = engine.guide(_box('bottle', 0.45, 0.4, 0.55, 0.5));
      expect(gTracked.state, GuidanceState.guiding);

      // Frame drop 1: enters reacquiring (not immediate lost alert)
      final gDrop1 = engine.guide(null);
      expect(gDrop1.state, GuidanceState.reacquiring);
      expect(gDrop1.isLost, isFalse);

      // Frame drop 2: stays in reacquiring
      final gDrop2 = engine.guide(null);
      expect(gDrop2.state, GuidanceState.reacquiring);
      expect(gDrop2.isLost, isFalse);

      // Frame drop 3: confirms lost
      final gDrop3 = engine.guide(null);
      expect(gDrop3.state, GuidanceState.lost);
      expect(gDrop3.isLost, isTrue);
    });

    test('handles uncertainty safely per PRD Section 10', () {
      final engine = GuidanceEngine(targetFriendlyName: 'bottle');
      final g = engine.guide(null, isCandidateUncertain: true);
      expect(g.isUncertain, isTrue);
      expect(
        g.phrase,
        contains(
          "I'm not sure that's your bottle. Please move the camera slowly.",
        ),
      );
    });
  });

  group('Multilingual Localization & TargetObjects', () {
    test('Hindi guidance produces proper localized phrases', () {
      final engine = GuidanceEngine(
        targetFriendlyName: 'bottle',
        language: AppLanguage.hindi,
      );

      // Left
      final gLeft = engine.guide(_box('bottle', 0.1, 0.4, 0.2, 0.5));
      expect(gLeft.phrase, 'बाएं मुड़ें।');

      // Forward
      final gFwd = engine.guide(_box('bottle', 0.48, 0.4, 0.52, 0.5));
      expect(gFwd.phrase, 'आगे बढ़ें।');

      // Found
      final gFound = engine.guide(_box('bottle', 0.25, 0.20, 0.75, 0.80));
      expect(gFound.phrase, 'रुकिए। बोतल मिल गया।');
    });

    test('Kannada guidance produces proper localized phrases', () {
      final engine = GuidanceEngine(
        targetFriendlyName: 'bottle',
        language: AppLanguage.kannada,
      );

      final gFound = engine.guide(_box('bottle', 0.25, 0.20, 0.75, 0.80));
      expect(gFound.phrase, 'ನಿಲ್ಲಿಸಿ. ಬಾಟಲ್ ಸಿಕ್ಕಿದೆ.');
    });

    test('Telugu and Tamil guidance produces proper localized phrases', () {
      final l10n = LocalizationService.instance;
      expect(
        l10n.stopObjectFound('bottle', AppLanguage.telugu),
        'ఆగండి. బాటిల్ దొరికింది.',
      );
      expect(
        l10n.stopObjectFound('bottle', AppLanguage.tamil),
        'நில்லுங்கள். பாட்டில் கிடைத்தது.',
      );
    });

    test('TargetObjects matches multilingual voice input queries', () {
      expect(TargetObjects.matchVoiceInput('मेरी बोतल ढूंढो'), 'bottle');
      expect(TargetObjects.matchVoiceInput('ನನ್ನ ಫೋನ್ ಹುಡುಕಿ'), 'phone');
      expect(TargetObjects.matchVoiceInput('నా రిమోట్ ఎక్కడ ఉంది'), 'remote');
      expect(TargetObjects.matchVoiceInput('புத்தகம் எங்கே'), 'book');
      expect(TargetObjects.matchVoiceInput('लैपटॉप'), 'laptop');
    });

    test('TargetObjects rejects unsupported objects in multiple languages', () {
      expect(TargetObjects.isQueryUnsupported('मेरी चाबी ढूंढो'), isTrue);
      expect(TargetObjects.isQueryUnsupported('ನನ್ನ ಕೀ ಎಲ್ಲಿದೆ'), isTrue);
      expect(TargetObjects.isQueryUnsupported('నా పర్సు ఎక్కడ ఉంది'), isTrue);
      expect(TargetObjects.isQueryUnsupported('சாவி எங்கே'), isTrue);
      expect(TargetObjects.isQueryUnsupported('चश्मा ढूंढो'), isTrue);
    });
  });
}
