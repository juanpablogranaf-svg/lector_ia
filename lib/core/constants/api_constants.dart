class ApiConstants {
  ApiConstants._();

  // Google Cloud Text-to-Speech
  static const String ttsBaseUrl = 'https://texttospeech.googleapis.com/v1';
  static const String ttsSynthesizeEndpoint = '/text:synthesize';
  static const String ttsVoicesEndpoint = '/voices';

  // Voces disponibles (Neural2 y Studio)
  static const Map<String, Map<String, String>> availableVoices = {
    'Español (España)': {
      'es-ES-Neural2-A': 'es-ES (Femenina Neural2)',
      'es-ES-Neural2-B': 'es-ES (Masculina Neural2)',
      'es-ES-Neural2-C': 'es-ES (Femenina Neural2 Alt)',
      'es-ES-Neural2-D': 'es-ES (Femenina Neural2 Alt 2)',
      'es-ES-Neural2-E': 'es-ES (Femenina Neural2 Alt 3)',
      'es-ES-Neural2-F': 'es-ES (Masculina Neural2 Alt)',
    },
    'Español (LATAM)': {
      'es-US-Neural2-A': 'es-US (Femenina Neural2)',
      'es-US-Neural2-B': 'es-US (Masculina Neural2)',
      'es-US-Neural2-C': 'es-US (Femenina Neural2 Alt)',
    },
    'English': {
      'en-US-Neural2-A': 'en-US (Male Neural2)',
      'en-US-Neural2-C': 'en-US (Female Neural2)',
      'en-US-Neural2-D': 'en-US (Male Neural2 Alt)',
      'en-US-Neural2-F': 'en-US (Female Neural2 Alt)',
      'en-US-Studio-O': 'en-US (Male Studio)',
      'en-US-Studio-Q': 'en-US (Female Studio)',
    },
    'Français': {
      'fr-FR-Neural2-A': 'fr-FR (Female Neural2)',
      'fr-FR-Neural2-B': 'fr-FR (Male Neural2)',
    },
    'Deutsch': {
      'de-DE-Neural2-A': 'de-DE (Female Neural2)',
      'de-DE-Neural2-B': 'de-DE (Male Neural2)',
    },
  };

  // Detección de idioma → código BCP-47
  static const Map<String, String> langCodeToVoice = {
    'es': 'es-ES-Neural2-A',
    'en': 'en-US-Neural2-C',
    'fr': 'fr-FR-Neural2-A',
    'de': 'de-DE-Neural2-A',
    'it': 'it-IT-Neural2-A',
    'pt': 'pt-BR-Neural2-A',
  };

  static const String defaultVoice = 'es-ES-Neural2-A';
  static const String defaultLanguageCode = 'es-ES';
  static const double defaultSpeakingRate = 1.0;
  static const double defaultPitch = 0.0;
  static const String audioEncoding = 'MP3';
  static const int sampleRateHertz = 24000;
}
