import '../models/app_language.dart';

/// Predefined translations for all guidance, assistant prompts, and UI labels.
///
/// Guidance phrases are strictly predefined per the PRD to ensure speed, predictability,
/// and reliability without runtime translation latency.
class LocalizationService {
  LocalizationService._();
  static final LocalizationService instance = LocalizationService._();

  static const Map<String, Map<AppLanguage, String>> _objectNames = {
    'bottle': {
      AppLanguage.english: 'bottle',
      AppLanguage.hindi: 'बोतल',
      AppLanguage.kannada: 'ಬಾಟಲ್',
      AppLanguage.telugu: 'బాటిల్',
      AppLanguage.tamil: 'பாட்டில்',
    },
    'phone': {
      AppLanguage.english: 'phone',
      AppLanguage.hindi: 'फ़ोन',
      AppLanguage.kannada: 'ಫೋನ್',
      AppLanguage.telugu: 'ఫోన్',
      AppLanguage.tamil: 'போன்',
    },
    'cup': {
      AppLanguage.english: 'cup',
      AppLanguage.hindi: 'कप',
      AppLanguage.kannada: 'ಕಪ್',
      AppLanguage.telugu: 'కప్పు',
      AppLanguage.tamil: 'கப்',
    },
    'book': {
      AppLanguage.english: 'book',
      AppLanguage.hindi: 'किताब',
      AppLanguage.kannada: 'ಪುಸ್ತಕ',
      AppLanguage.telugu: 'పుస్తకం',
      AppLanguage.tamil: 'புத்தகம்',
    },
    'bag': {
      AppLanguage.english: 'bag',
      AppLanguage.hindi: 'बैग',
      AppLanguage.kannada: 'ಬ್ಯಾಗ್',
      AppLanguage.telugu: 'బ్యాగ్',
      AppLanguage.tamil: 'பை',
    },
    'backpack': {
      AppLanguage.english: 'backpack',
      AppLanguage.hindi: 'बैकपैक',
      AppLanguage.kannada: 'ಬ್ಯಾಕ್‌ಪ್ಯಾಕ್',
      AppLanguage.telugu: 'బ్యాక్‌ప్యాక్',
      AppLanguage.tamil: 'முதுகுப்பை',
    },
    'remote': {
      AppLanguage.english: 'remote',
      AppLanguage.hindi: 'रिमोट',
      AppLanguage.kannada: 'ರಿಮೋಟ್',
      AppLanguage.telugu: 'రిమోట్',
      AppLanguage.tamil: 'ரிமோட்',
    },
    'keyboard': {
      AppLanguage.english: 'keyboard',
      AppLanguage.hindi: 'कीबोर्ड',
      AppLanguage.kannada: 'ಕೀಬೋರ್ಡ್',
      AppLanguage.telugu: 'కీబోర్డ్',
      AppLanguage.tamil: 'விசைப்பலகை',
    },
    'mouse': {
      AppLanguage.english: 'mouse',
      AppLanguage.hindi: 'माउस',
      AppLanguage.kannada: 'ಮೌಸ್',
      AppLanguage.telugu: 'మౌస్',
      AppLanguage.tamil: 'மவுஸ்',
    },
    'laptop': {
      AppLanguage.english: 'laptop',
      AppLanguage.hindi: 'लैपटॉप',
      AppLanguage.kannada: 'ಲ್ಯಾಪ್‌ಟಾಪ್',
      AppLanguage.telugu: 'ల్యాప్‌టాప్',
      AppLanguage.tamil: 'மடிக்கணினி',
    },
  };

  String objectName(String friendlyKey, AppLanguage lang) {
    final key = friendlyKey.toLowerCase().trim();
    return _objectNames[key]?[lang] ?? friendlyKey;
  }

  // Directional guidance
  String moveLeft(AppLanguage lang) => switch (lang) {
    AppLanguage.english => 'Move left.',
    AppLanguage.hindi => 'बाएं मुड़ें।',
    AppLanguage.kannada => 'ಎಡಕ್ಕೆ ಸಾಗಿ.',
    AppLanguage.telugu => 'ఎడమవైపు వెళ్లండి.',
    AppLanguage.tamil => 'இடதுபுறம் செல்லுங்கள்.',
  };

  String moveSlightlyLeft(AppLanguage lang) => switch (lang) {
    AppLanguage.english => 'Move slightly left.',
    AppLanguage.hindi => 'थोड़ा बाएं जाएं।',
    AppLanguage.kannada => 'ಸ್ವಲ್ಪ ಎಡಕ್ಕೆ ಸಾಗಿ.',
    AppLanguage.telugu => 'కొద్దిగా ఎడమవైపు వెళ్లండి.',
    AppLanguage.tamil => 'சிறிது இடதுபுறம் செல்லுங்கள்.',
  };

  String moveForward(AppLanguage lang) => switch (lang) {
    AppLanguage.english => 'Move forward.',
    AppLanguage.hindi => 'आगे बढ़ें।',
    AppLanguage.kannada => 'ಮುಂದೆ ಸಾಗಿ.',
    AppLanguage.telugu => 'ముందుకు వెళ్లండి.',
    AppLanguage.tamil => 'முன்னோக்கி செல்லுங்கள்.',
  };

  String moveSlightlyRight(AppLanguage lang) => switch (lang) {
    AppLanguage.english => 'Move slightly right.',
    AppLanguage.hindi => 'थोड़ा दाएं जाएं।',
    AppLanguage.kannada => 'ಸ್ವಲ್ಪ ಬಲಕ್ಕೆ ಸಾಗಿ.',
    AppLanguage.telugu => 'కొద్దిగా కుడివైపు వెళ్లండి.',
    AppLanguage.tamil => 'சிறிது வலதுபுறம் செல்லுங்கள்.',
  };

  String moveRight(AppLanguage lang) => switch (lang) {
    AppLanguage.english => 'Move right.',
    AppLanguage.hindi => 'दाएं मुड़ें।',
    AppLanguage.kannada => 'ಬಲಕ್ಕೆ ಸಾಗಿ.',
    AppLanguage.telugu => 'కుడివైపు వెళ్లండి.',
    AppLanguage.tamil => 'வலதுபுறம் செல்லுங்கள்.',
  };

  String youAreGettingCloser(AppLanguage lang) => switch (lang) {
    AppLanguage.english => "You're getting closer.",
    AppLanguage.hindi => 'आप करीब आ रहे हैं।',
    AppLanguage.kannada => 'ನೀವು ಹತ್ತಿರವಾಗುತ್ತಿದ್ದೀರಿ.',
    AppLanguage.telugu => 'మీరు దగ్గరకు వస్తున్నారు.',
    AppLanguage.tamil => 'நீங்கள் அருகில் வருகிறீர்கள்.',
  };

  String objectIsClose(AppLanguage lang) => switch (lang) {
    AppLanguage.english => 'The object is close.',
    AppLanguage.hindi => 'वस्तु पास है।',
    AppLanguage.kannada => 'ವಸ್ತು ಹತ್ತಿರದಲ್ಲಿದೆ.',
    AppLanguage.telugu => 'వస్తువు దగ్గరగా ఉంది.',
    AppLanguage.tamil => 'பொருள் அருகில் உள்ளது.',
  };

  String stopObjectFound(String friendlyTarget, AppLanguage lang) {
    final target = objectName(friendlyTarget, lang);
    return switch (lang) {
      AppLanguage.english => 'Stop. $target found.',
      AppLanguage.hindi => 'रुकिए। $target मिल गया।',
      AppLanguage.kannada => 'ನಿಲ್ಲಿಸಿ. $target ಸಿಕ್ಕಿದೆ.',
      AppLanguage.telugu => 'ఆగండి. $target దొరికింది.',
      AppLanguage.tamil => 'நில்லுங்கள். $target கிடைத்தது.',
    };
  }

  String objectDetected(String friendlyTarget, AppLanguage lang) {
    final target = objectName(friendlyTarget, lang);
    return switch (lang) {
      AppLanguage.english => '$target detected.',
      AppLanguage.hindi => '$target मिल गया है।',
      AppLanguage.kannada => '$target ಪತ್ತೆಯಾಗಿದೆ.',
      AppLanguage.telugu => '$target గుర్తించబడింది.',
      AppLanguage.tamil => '$target கண்டறியப்பட்டது.',
    };
  }

  String objectLost(AppLanguage lang) => switch (lang) {
    AppLanguage.english => 'I lost the object. Move the camera slowly.',
    AppLanguage.hindi => 'वस्तु खो गई है। कृपया कैमरा धीरे-धीरे घुमाएं।',
    AppLanguage.kannada =>
      'ವಸ್ತು ಕಾಣಿಸುತ್ತಿಲ್ಲ. ಕ್ಯಾಮೆರಾವನ್ನು ನಿಧಾನವಾಗಿ ಚಲಿಸಿ.',
    AppLanguage.telugu => 'వస్తువు కనిపించడం లేదు. కెమెరాను నెమ్మదిగా కదపండి.',
    AppLanguage.tamil => 'பொருள் தெரியவில்லை. கேமராவை மெதுவாக நகர்த்தவும்.',
  };

  String reacquiring(AppLanguage lang) => switch (lang) {
    AppLanguage.english => 'Reacquiring object. Hold steady.',
    AppLanguage.hindi => 'वस्तु को पुनः खोजा जा रहा है। स्थिर रखें।',
    AppLanguage.kannada =>
      'ವಸ್ತುವನ್ನು ಮತ್ತೆ ಹುಡುಕಲಾಗುತ್ತಿದೆ. ಸ್ಥಿರವಾಗಿ ಹಿಡಿಯಿರಿ.',
    AppLanguage.telugu => 'వస్తువు కోసం మళ్లీ చూస్తున్నాము. స్థిరంగా ఉంచండి.',
    AppLanguage.tamil => 'பொருளை மீண்டும் தேடுகிறது. நிலையாக பிடிக்கவும்.',
  };

  String scanningUncertain(String friendlyTarget, AppLanguage lang) {
    final target = objectName(friendlyTarget, lang);
    return switch (lang) {
      AppLanguage.english =>
        "I'm not sure that's your $target. Please move the camera slowly.",
      AppLanguage.hindi =>
        'मुझे पक्का नहीं पता कि यह आपकी $target है। कृपया कैमरा धीरे-धीरे घुमाएं।',
      AppLanguage.kannada =>
        'ಇದು ನಿಮ್ಮ $target ಎಂದು ಖಚಿತವಿಲ್ಲ. ಕ್ಯಾಮೆರಾವನ್ನು ನಿಧಾನವಾಗಿ ಚಲಿಸಿ.',
      AppLanguage.telugu =>
        'ఇది మీ $target అని ఖచ్చితంగా లేదు. కెమెరాను నెమ్మదిగా కదపండి.',
      AppLanguage.tamil =>
        'இது உங்கள் $target என்று உறுதியாக தெரியவில்லை. கேமராவை மெதுவாக நகர்த்தவும்.',
    };
  }

  String scanRoom(AppLanguage lang) => switch (lang) {
    AppLanguage.english =>
      "I can't identify the object yet. Please slowly scan the room.",
    AppLanguage.hindi =>
      'अभी वस्तु नहीं पहचानी जा सकी। कृपया कमरे को धीरे-धीरे स्कैन करें।',
    AppLanguage.kannada =>
      'ವಸ್ತು ಇನ್ನೂ ಗುರುತಿಸಲಾಗಿಲ್ಲ. ದಯವಿಟ್ಟು ಕೋಣೆಯನ್ನು ನಿಧಾನವಾಗಿ ಸ್ಕ್ಯಾನ್ ಮಾಡಿ.',
    AppLanguage.telugu =>
      'ఇంకా వస్తువు గుర్తించబడలేదు. దయచేసి గదిని నెమ్మదిగా స్కాన్ చేయండి.',
    AppLanguage.tamil =>
      'பொருளை இன்னும் அடையாளம் காண முடியவில்லை. அறையை மெதுவாக ஸ்கேன் செய்யவும்.',
  };

  String unsupportedObject(AppLanguage lang) => switch (lang) {
    AppLanguage.english => "I can't reliably find that object yet.",
    AppLanguage.hindi =>
      'मैं अभी उस वस्तु को भरोसेमंद तरीके से नहीं ढूंढ सकता।',
    AppLanguage.kannada =>
      'ನಾನು ಆ ವಸ್ತುವನ್ನು ಇನ್ನೂ ವಿಶ್ವಾಸಾರ್ಹವಾಗಿ ಹುಡುಕಲು ಸಾಧ್ಯವಿಲ್ಲ.',
    AppLanguage.telugu => 'నేను ఆ వస్తువును ఇంకా ఖచ్చితంగా కనుగొనలేను.',
    AppLanguage.tamil =>
      'என்னால் இன்னும் அந்தப் பொருளை நம்பத்தகுந்த முறையில் கண்டுபிடிக்க முடியாது.',
  };

  String searchingTarget(String friendlyTarget, AppLanguage lang) {
    final target = objectName(friendlyTarget, lang);
    return switch (lang) {
      AppLanguage.english => 'Okay. Looking for your $target.',
      AppLanguage.hindi => 'ठीक है। आपकी $target ढूंढ रहा हूँ।',
      AppLanguage.kannada => 'ಸರಿ. ನಿಮ್ಮ $target ಹುಡುಕುತ್ತಿದ್ದೇನೆ.',
      AppLanguage.telugu => 'సరే. మీ $target కోసం వెతుకుతున్నాను.',
      AppLanguage.tamil => 'சரி. உங்கள் $target தேடுகிறேன்.',
    };
  }

  // Onboarding & Friendly Assistant Strings
  String welcomeGreeting(AppLanguage lang) => switch (lang) {
    AppLanguage.english => "Hi, I'm FindIt.",
    AppLanguage.hindi => 'नमस्ते, मैं FindIt हूँ।',
    AppLanguage.kannada => 'ನಮಸ್ಕಾರ, ನಾನು FindIt.',
    AppLanguage.telugu => 'నమస్తే, నేను FindIt.',
    AppLanguage.tamil => 'வணக்கம், நான் FindIt.',
  };

  String askName(AppLanguage lang) => switch (lang) {
    AppLanguage.english => 'Before we start, what should I call you?',
    AppLanguage.hindi => 'शुरू करने से पहले, मैं आपको किस नाम से बुलाऊं?',
    AppLanguage.kannada => 'ಪ್ರಾರಂಭಿಸುವ ಮೊದಲು, ನಾನು ನಿಮ್ಮನ್ನು ಏನಂತ ಕರೆಯಲಿ?',
    AppLanguage.telugu => 'మనం ప్రారంభించే ముందు, నేను మిమ్మల్ని ఏమని పిలవాలి?',
    AppLanguage.tamil =>
      'தொடங்குவதற்கு முன், நான் உங்களை என்னவென்று அழைக்க வேண்டும்?',
  };

  String niceToMeetYou(String name, AppLanguage lang) => switch (lang) {
    AppLanguage.english => 'Nice to meet you, $name.',
    AppLanguage.hindi => 'आपसे मिलकर अच्छा लगा, $name।',
    AppLanguage.kannada => 'ನಿಮ್ಮನ್ನು ಭೇಟಿಯಾಗಿದ್ದು ಸಂತೋಷವಾಯಿತು, $name.',
    AppLanguage.telugu => 'మిమ్మల్ని కలవడం ఆనందంగా ఉంది, $name.',
    AppLanguage.tamil => 'உங்களை சந்தித்ததில் மகிழ்ச்சி, $name.',
  };

  String askLanguage(AppLanguage lang) => switch (lang) {
    AppLanguage.english => 'Which language would you like me to use?',
    AppLanguage.hindi => 'आप मुझसे किस भाषा में बात करना चाहेंगे?',
    AppLanguage.kannada => 'ನಾನು ಯಾವ ಭಾಷೆಯಲ್ಲಿ ಮಾತನಾಡಬೇಕೆಂದು ನೀವು ಬಯಸುತ್ತೀರಿ?',
    AppLanguage.telugu => 'నేను మీతో ఏ భాషలో మాట్లాడాలని మీరు కోరుకుంటున్నారు?',
    AppLanguage.tamil => 'நான் உங்களிடம் எந்த மொழியில் பேச வேண்டும்?',
  };

  String languageChangedAck(AppLanguage lang) => switch (lang) {
    AppLanguage.english => 'Great. I will speak with you in English.',
    AppLanguage.hindi => 'ठीक है। अब मैं आपसे हिंदी में बात करूँगा।',
    AppLanguage.kannada =>
      'ಸರಿ. ಇನ್ನು ನಾನು ನಿಮ್ಮೊಂದಿಗೆ ಕನ್ನಡದಲ್ಲಿ ಮಾತನಾಡುತ್ತೇನೆ.',
    AppLanguage.telugu => 'సరే. ఇకపై నేను మీతో తెలుగులో మాట్లాడతాను.',
    AppLanguage.tamil => 'சரி. இனி நான் உங்களிடம் தமிழில் பேசுவேன்.',
  };

  String howAreYou(AppLanguage lang) => switch (lang) {
    AppLanguage.english => 'How are you today?',
    AppLanguage.hindi => 'आज आप कैसे हैं?',
    AppLanguage.kannada => 'ಇವತ್ತು ಹೇಗಿದ್ದೀರಿ?',
    AppLanguage.telugu => 'ఈ రోజు మీరు ఎలా ఉన్నారు?',
    AppLanguage.tamil => 'இன்று நீங்கள் எப்படி இருக்கிறீர்கள்?',
  };

  String howCanIHelp(AppLanguage lang) => switch (lang) {
    AppLanguage.english => 'What would you like me to help you with?',
    AppLanguage.hindi => 'मैं आपकी किस चीज़ में मदद कर सकता हूँ?',
    AppLanguage.kannada => 'ನಾನು ನಿಮಗೆ ಯಾವ ವಿಷಯದಲ್ಲಿ ಸಹಾಯ ಮಾಡಲಿ?',
    AppLanguage.telugu => 'నేను మీకు దేనిలో సహాయం చేయాలి?',
    AppLanguage.tamil => 'நான் உங்களுக்கு எதில் உதவ வேண்டும்?',
  };

  String findSomething(AppLanguage lang) => switch (lang) {
    AppLanguage.english => 'Find something',
    AppLanguage.hindi => 'कुछ ढूंढें',
    AppLanguage.kannada => 'ಏನನ್ನಾದರೂ ಹುಡುಕಿ',
    AppLanguage.telugu => 'ఏదైనా వెతకండి',
    AppLanguage.tamil => 'ஏதாவது தேடுங்கள்',
  };

  String describeSurroundings(AppLanguage lang) => switch (lang) {
    AppLanguage.english => 'Describe my surroundings',
    AppLanguage.hindi => 'आस-पास का वर्णन करें',
    AppLanguage.kannada => 'ನನ್ನ ಸುತ್ತಮುತ್ತಲಿನ ವಿವರಣೆ ನೀಡಿ',
    AppLanguage.telugu => 'నా పరిసరాలను వివరించండి',
    AppLanguage.tamil => 'என் சுற்றத்தை விவரிக்கவும்',
  };

  String helpMeUnderstand(AppLanguage lang) => switch (lang) {
    AppLanguage.english => 'Help me understand something',
    AppLanguage.hindi => 'मुझे कुछ समझने में मदद करें',
    AppLanguage.kannada => 'ಏನನ್ನಾದರೂ ಅರ್ಥಮಾಡಿಕೊಳ್ಳಲು ಸಹಾಯ ಮಾಡಿ',
    AppLanguage.telugu => 'ఏదైనా అర్థం చేసుకోవడానికి సహాయం చేయండి',
    AppLanguage.tamil => 'ஏதாவது புரிந்து கொள்ள உதவுங்கள்',
  };

  String settings(AppLanguage lang) => switch (lang) {
    AppLanguage.english => 'Settings',
    AppLanguage.hindi => 'सेटिंग्स',
    AppLanguage.kannada => 'ಸೆಟ್ಟಿಂಗ್‌ಗಳು',
    AppLanguage.telugu => 'సెట్టింగ్‌లు',
    AppLanguage.tamil => 'அமைப்புகள்',
  };

  String help(AppLanguage lang) => switch (lang) {
    AppLanguage.english => 'Help',
    AppLanguage.hindi => 'मदद',
    AppLanguage.kannada => 'ಸಹಾಯ',
    AppLanguage.telugu => 'సహాయం',
    AppLanguage.tamil => 'உதவி',
  };

  String stop(AppLanguage lang) => switch (lang) {
    AppLanguage.english => 'STOP',
    AppLanguage.hindi => 'रुकें',
    AppLanguage.kannada => 'ನಿಲ್ಲಿಸಿ',
    AppLanguage.telugu => 'ఆగండి',
    AppLanguage.tamil => 'நில்லுங்கள்',
  };

  String resume(AppLanguage lang) => switch (lang) {
    AppLanguage.english => 'RESUME',
    AppLanguage.hindi => 'जारी रखें',
    AppLanguage.kannada => 'ಮುಂದುವರಿಸಿ',
    AppLanguage.telugu => 'కొనసాగించండి',
    AppLanguage.tamil => 'தொடரவும்',
  };

  String alarmSilenced(AppLanguage lang) => switch (lang) {
    AppLanguage.english => 'Alarm silenced. Phone found.',
    AppLanguage.hindi => 'अलार्म बंद हो गया। फ़ोन मिल गया।',
    AppLanguage.kannada => 'ಅಲಾರಂ ನಿಲ್ಲಿಸಲಾಗಿದೆ. ಫೋನ್ ಸಿಕ್ಕಿತು.',
    AppLanguage.telugu => 'అలారం ఆపివేయబడింది. ఫోన్ దొరికింది.',
    AppLanguage.tamil => 'அலாரம் நிறுத்தப்பட்டது. போன் கிடைத்தது.',
  };

  String lostPhoneAlert(AppLanguage lang) => switch (lang) {
    AppLanguage.english => "I'm right here. Follow my voice or alarm.",
    AppLanguage.hindi => 'मैं यहीं हूँ। मेरी आवाज़ या अलार्म की दिशा में आइए।',
    AppLanguage.kannada => 'ನಾನು ಇಲ್ಲೇ ಇದ್ದೇನೆ. ನನ್ನ ಧ್ವನಿ ಅಥವಾ ಅಲಾರಂ ಅನುಸರಿಸಿ.',
    AppLanguage.telugu => 'నేను ఇక్కడే ఉన్నాను. నా స్వరాన్ని లేదా అలారంను అనుసరించండి.',
    AppLanguage.tamil => 'நான் இங்கே இருக்கிறேன். என் குரல் அல்லது அலாரத்தைப் பின்பற்றுங்கள்.',
  };
}
