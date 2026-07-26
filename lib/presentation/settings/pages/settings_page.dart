import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKeyController.text = prefs.getString(AppConstants.prefApiKey) ?? '';
      _selectedVoice = prefs.getString(AppConstants.prefTtsVoice) ?? ApiConstants.defaultVoice;
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefApiKey, _apiKeyController.text.trim());
    await prefs.setString(AppConstants.prefTtsVoice, _selectedVoice);
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ─── API Key Section ─────────────────────────────────────────────
          _SectionHeader(title: 'Google Cloud TTS', icon: Icons.record_voice_over, color: cs.primary),
          const SizedBox(height: 12),

          // Instrucciones
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
              ],
            ),
          ),
          const SizedBox(height: 16),

          // API Key input
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

          // ─── Voz Section ─────────────────────────────────────────────────
          _SectionHeader(title: 'Voz de síntesis', icon: Icons.spatial_audio, color: cs.secondary),
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
                      valueColor: AlwaysStoppedAnimation(Colors.teal),
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
