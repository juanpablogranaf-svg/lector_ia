# LectorIA 📖🔊

**E-reader con TTS Neural y reproducción continua en segundo plano.**

Inspirado en ReadEra, pero con dos características premium desbloqueadas:
- **Voz Natural IA** con Google Cloud TTS (Neural2/Studio)
- **Reproducción con pantalla bloqueada** mediante Foreground Service en Android

---

## 🚀 Instalación y Puesta en Marcha

### 1. Instalar Flutter

Si aún no tienes Flutter instalado:

```powershell
# Opción 1: Descargar desde la web oficial
# https://docs.flutter.dev/get-started/install/windows

# Opción 2: Usando Chocolatey
choco install flutter

# Opción 3: Winget
winget install Google.Flutter
```

Verifica la instalación:
```powershell
flutter doctor
```

### 2. Instalar dependencias del proyecto

```powershell
cd "c:\Users\jpgranya\Desktop\Antigravity - App"
flutter pub get
```

### 3. Compilar y ejecutar en un dispositivo Android

Conecta tu dispositivo Android por USB con Depuración USB activada:

```powershell
flutter devices              # Ver dispositivos disponibles
flutter run                  # Ejecutar en debug
flutter run --release        # Ejecutar en release (optimizado)
```

Para compilar el APK:
```powershell
flutter build apk --release
# El APK quedará en: build/app/outputs/flutter-apk/app-release.apk
```

---

## ⚙️ Configuración de la API Key de Google Cloud TTS

### Obtener la API Key

1. Ve a [Google Cloud Console](https://console.cloud.google.com)
2. Crea un proyecto nuevo o selecciona uno existente
3. Activa la API **"Cloud Text-to-Speech"**:
   - Menú → APIs y Servicios → Biblioteca → buscar "Text-to-Speech" → Habilitar
4. Crea las credenciales:
   - Menú → APIs y Servicios → Credenciales → Crear credenciales → Clave de API
5. (Opcional) Restringe la clave a solo la API de TTS

### Ingresar la clave en la app

Abre la app → Toca el ícono ⚙️ (Ajustes) → Ingresa tu API Key → Guardar

---

## 🏗️ Arquitectura del Proyecto

```
lib/
├── main.dart                    # Bootstrap: AudioService init + DI
├── app/
│   ├── app.dart                 # MaterialApp con BLoC providers
│   └── router.dart              # GoRouter: /library, /reader/:id, /settings
├── core/
│   ├── constants/               # ApiConstants, AppConstants
│   ├── di/injection_container.dart  # GetIt DI setup
│   ├── errors/failures.dart     # Tipos de error tipados
│   ├── theme/app_theme.dart     # Temas Dark/Light/Sepia
│   └── utils/
│       ├── text_chunker.dart    # ⭐ Chunking inteligente de texto
│       └── audio_cache_manager.dart  # ⭐ Caché LRU de audio (200MB)
├── data/
│   ├── datasources/
│   │   ├── local/               # SQLite: libros, progreso, capítulos
│   │   └── remote/
│   │       └── tts_remote_datasource.dart  # ⭐ Cliente Google Cloud TTS
│   └── models/                  # BookModel, ReadingProgressModel
├── presentation/
│   ├── library/
│   │   ├── bloc/library_bloc.dart  # Escaneo, búsqueda, ordenación
│   │   ├── pages/library_page.dart
│   │   └── widgets/             # BookCard, ScanProgressIndicator
│   ├── reader/
│   │   ├── bloc/reader_bloc.dart   # Lectura, TTS, progreso
│   │   ├── pages/reader_page.dart  # Visor EPUB/PDF/TXT
│   │   └── widgets/             # TtsPlayerBar, ReaderSettingsPanel
│   └── settings/pages/settings_page.dart
└── services/
    └── audio_service/
        ├── background_audio_handler.dart  # ⭐ Foreground Service Handler
        └── audio_session_manager.dart     # ⭐ Audio Focus (llamadas, auriculares)
```

---

## 🎯 Características Implementadas

### 📚 Biblioteca
- Escaneo automático de almacenamiento (EPUB, PDF, TXT)
- Stream de resultados en tiempo real con contador de progreso
- Grid de libros con portadas generadas automáticamente (color único por título)
- Búsqueda por título y autor
- Ordenación: Añadido recientemente / Última apertura / Título / Autor
- Barra de progreso de lectura en cada libro

### 📖 Lector
- EPUB con `epub_view` (texto nativo con tipografía configurable)
- PDF con `pdfx` (renderizado con PDFium)
- TXT con scroll nativo y resaltado del chunk TTS actual
- Modos de tema: **Oscuro** / **Claro** / **Sepia**
- Tamaño de fuente ajustable (12-32px) con preview en tiempo real
- Guardado automático de progreso (scroll + capítulo + chunk TTS)
- Controles que se ocultan/muestran al tocar la pantalla

### 🔊 TTS Neural (Google Cloud)
- Voces **Neural2** y **Studio** de alta fidelidad
- Detección automática de idioma (español, inglés, francés, alemán, portugués)
- **Chunking inteligente**: divide por párrafos → oraciones → cláusulas → longitud
- **Caché LRU de 200MB**: evita repetir llamadas a la API
- Rate limiting: 1 request concurrente + retry con exponential backoff
- Pre-carga de los próximos 3 chunks en background
- Velocidades: 0.75x / 1.0x / 1.25x / 1.5x / 1.75x / 2.0x

### 🔒 Reproducción con Pantalla Bloqueada
- **Foreground Service** en Android (mediaPlayback type)
- Notificación multimedia con controles: ⏮ Anterior / ⏸ Pausa / ⏭ Siguiente / ⏹ Stop
- **Audio Focus**: pausa automática al recibir llamadas
- **Becoming Noisy**: pausa al desenchufar auriculares
- Duck audio en notificaciones breves

---

## 📦 Dependencias Principales

| Paquete | Versión | Uso |
|---------|---------|-----|
| `audio_service` | 0.18.15 | Foreground Service + media controls |
| `just_audio` | 0.9.40 | Reproducción de MP3 |
| `audio_session` | 0.1.21 | Audio Focus management |
| `epub_view` | 4.3.2 | Visor EPUB nativo |
| `pdfx` | 2.6.0 | Renderizado PDF con PDFium |
| `flutter_bloc` | 8.1.6 | State management |
| `dio` | 5.7.0 | Cliente HTTP para TTS API |
| `sqflite` | 2.3.3 | Base de datos local |
| `crypto` | 3.0.3 | Hash MD5 para claves de caché |
| `rxdart` | 0.27.7 | Debounce del scroll |

---

## 💡 Notas de Desarrollo

- **minSdk**: 24 (Android 7.0) — requerido por `audio_service`
- **targetSdk**: 34 (Android 14)
- El `foregroundServiceType="mediaPlayback"` es **obligatorio** en Android 10+ para reproducción continua
- En Android 13+, el permiso `POST_NOTIFICATIONS` debe solicitarse en runtime
- El caché de audio se guarda en `getApplicationCacheDirectory()/audio_cache/`

---

## 📝 Licencia

Proyecto privado — todos los derechos reservados.
