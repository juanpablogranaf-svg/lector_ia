import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/audio_cache_manager.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _apiKeyController;
  bool _apiKeyVisible = false;
  String _selectedVoice = ApiConstants.defaultVoice;
  String _selectedVoiceNative = '';
  String _selectedProvider = 'google'; // 'google' o 'native'
  bool _isSaving = false;

  final FlutterTts _flutterTts = FlutterTts();
  List<Map<String, String>> _nativeVoices = [];
  bool _loadingNativeVoices = false;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _loadSettings();
    _initNativeTts();
  }

  Future<void> _initNativeTts() async {
    setState(() => _loadingNativeVoices = true);
    try {
      final voices = await _flutterTts.getVoices;
      if (voices != null) {
        final List<Map<String, String>> parsedVoices = [];
        for (final dynamic voice in voices) {
          if (voice is Map) {
            final name = voice['name']?.toString() ?? '';
            final locale = voice['locale']?.toString() ?? '';
            if (name.isNotEmpty && locale.isNotEmpty) {
              final lowerLocale = locale.toLowerCase();
              // Limitar estrictamente a español (es), francés (fr) e inglés (en)
              if (lowerLocale.startsWith('es') ||
                  lowerLocale.startsWith('fr') ||
                  lowerLocale.startsWith('en')) {
                parsedVoices.add({
                  'name': name,
                  'locale': locale,
                });
              }
            }
          }
        }
        // Ordenar voces por locale
        parsedVoices.sort((a, b) => a['locale']!.compareTo(b['locale']!));
        setState(() {
          _nativeVoices = parsedVoices;
        });
      }
    } catch (e) {
      debugPrint('Error obteniendo voces locales: $e');
    } finally {
      setState(() => _loadingNativeVoices = false);
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKeyController.text = prefs.getString(AppConstants.prefApiKey) ?? '';
      _selectedVoice = prefs.getString(AppConstants.prefTtsVoice) ?? ApiConstants.defaultVoice;
      _selectedVoiceNative = prefs.getString(AppConstants.prefTtsVoiceNative) ?? '';
      _selectedProvider = prefs.getString(AppConstants.prefTtsProvider) ?? 'google';
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefApiKey, _apiKeyController.text.trim());
    await prefs.setString(AppConstants.prefTtsVoice, _selectedVoice);
    await prefs.setString(AppConstants.prefTtsVoiceNative, _selectedVoiceNative);
    await prefs.setString(AppConstants.prefTtsProvider, _selectedProvider);
    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 10),
              Text('Ajustes guardados correctamente'),
            ],
          ),
          backgroundColor: const Color(0xFF6C63FF),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isGoogle = _selectedProvider == 'google';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes de Voz'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ─── Motor de voz selector ─────────────────────────────────────────
          _SectionHeader(title: 'Motor de Voz / Proveedor', icon: Icons.settings_voice, color: cs.primary),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedProvider,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Motor de síntesis activo',
              prefixIcon: Icon(Icons.volume_up),
            ),
            items: const [
              DropdownMenuItem(
                value: 'google',
                child: Text(
                  'Google Cloud TTS (Online / Alta calidad)',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DropdownMenuItem(
                value: 'native',
                child: Text(
                  'Voz del dispositivo (Offline / Gratis)',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedProvider = val);
              }
            },
          ),
          const SizedBox(height: 24),

          // ─── Google Cloud TTS Block ────────────────────────────────────────
          if (isGoogle) ...[
            _SectionHeader(title: 'Google Cloud TTS', icon: Icons.cloud_queue, color: cs.primary),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.primary.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: cs.primary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Cómo obtener tu API Key',
                        style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '1. Ve a console.cloud.google.com\n'
                    '2. Crea un proyecto nuevo o selecciona uno\n'
                    '3. Habilita la API "Cloud Text-to-Speech"\n'
                    '4. Ve a "Credenciales" → "Crear API Key"\n'
                    '5. Pega la clave aquí abajo',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withOpacity(0.7),
                      height: 1.6,
                    ),
                  ),
                  const Divider(height: 24, color: Colors.white12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb_outline, color: Colors.amber, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '💡 Google Cloud ofrece 1 millón de caracteres gratis al mes. Puedes configurar una alerta de presupuesto de 0€ en la consola para evitar cobros.',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withOpacity(0.85),
                            fontStyle: FontStyle.italic,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _apiKeyController,
              obscureText: !_apiKeyVisible,
              decoration: InputDecoration(
                labelText: 'API Key de Google Cloud',
                hintText: 'AIza...',
                prefixIcon: const Icon(Icons.key),
                suffixIcon: IconButton(
                  icon: Icon(_apiKeyVisible ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _apiKeyVisible = !_apiKeyVisible),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _SectionHeader(title: 'Voz de síntesis (Google)', icon: Icons.spatial_audio, color: cs.secondary),
            const SizedBox(height: 12),
            ...ApiConstants.availableVoices.entries.map((langEntry) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      langEntry.key,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withOpacity(0.5),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  ...langEntry.value.entries.map((voiceEntry) {
                    return RadioListTile<String>(
                      value: voiceEntry.key,
                      groupValue: _selectedVoice,
                      title: Text(voiceEntry.value, style: const TextStyle(fontSize: 14)),
                      subtitle: Text(
                        voiceEntry.key,
                        style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5)),
                      ),
                      activeColor: cs.primary,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (v) => setState(() => _selectedVoice = v ?? _selectedVoice),
                    );
                  }),
                ],
              );
            }),
          ] else ...[
            // ─── Voz del Dispositivo (Nativo) Block ──────────────────────────
            _SectionHeader(title: 'Voces del dispositivo (Nativo)', icon: Icons.phone_android, color: cs.secondary),
            const SizedBox(height: 12),
            if (_loadingNativeVoices)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_nativeVoices.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'No se detectaron voces locales de TTS. Comprueba el motor de voz nativo en los ajustes del dispositivo.',
                  style: TextStyle(color: cs.onSurface.withOpacity(0.5)),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _nativeVoices.length,
                itemBuilder: (context, index) {
                  final voice = _nativeVoices[index];
                  final name = voice['name']!;
                  final locale = voice['locale']!;
                  return RadioListTile<String>(
                    value: name,
                    groupValue: _selectedVoiceNative,
                    title: Text(name, style: const TextStyle(fontSize: 14)),
                    subtitle: Text(
                      locale,
                      style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5)),
                    ),
                    activeColor: cs.primary,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _selectedVoiceNative = v);
                      }
                    },
                  );
                },
              ),
          ],

          const SizedBox(height: 24),

          // ─── Caché Section ───────────────────────────────────────────────
          _SectionHeader(title: 'Caché de Audio', icon: Icons.storage, color: Colors.teal),
          const SizedBox(height: 12),
          FutureBuilder<void>(
            future: AudioCacheManager.instance.initialize(),
            builder: (context, _) {
              final sizeMB = AudioCacheManager.instance.currentSizeMB;
              final count = AudioCacheManager.instance.cachedChunksCount;
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outline.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Espacio usado: ${sizeMB.toStringAsFixed(1)} MB / ${AppConstants.audioCacheMaxMB} MB'),
                        Text('$count fragmentos', style: TextStyle(color: cs.onSurface.withOpacity(0.5), fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: (sizeMB / AppConstants.audioCacheMaxMB).clamp(0, 1),
                      backgroundColor: cs.surfaceVariant,
                      valueColor: const AlwaysStoppedAnimation(Colors.teal),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text('Limpiar caché', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                      ),
                      onPressed: () async {
                        await AudioCacheManager.instance.clearAll();
                        setState(() {});
                      },
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 32),

          // Save button
          ElevatedButton.icon(
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save),
            label: Text(_isSaving ? 'Guardando...' : 'Guardar Ajustes'),
            onPressed: _isSaving ? null : _saveSettings,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const _SectionHeader({required this.title, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: color.withOpacity(0.3))),
      ],
    );
  }
}
