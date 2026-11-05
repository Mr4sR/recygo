import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tiny SFX player. Errors are swallowed (respect silent mode / init failure).
class Sfx {
  Sfx._();
  static final Sfx instance = Sfx._();

  static const String _key = 'sfx_enabled';
  bool _enabled = true;
  bool get enabled => _enabled;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_key) ?? true;
    } catch (_) {
      _enabled = true;
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (_) {}
  }

  Future<void> _play(String asset) async {
    if (!_enabled) return;
    try {
      final player = AudioPlayer();
      await player.play(AssetSource(asset), volume: 0.5);
      player.onPlayerComplete.listen((_) => player.dispose());
    } catch (_) {
      // Ignore audio init failures.
    }
  }

  Future<void> tap() => _play('sfx/tap.mp3');
  Future<void> shutter() => _play('sfx/shutter.mp3');
  Future<void> success() => _play('sfx/success.mp3');
  Future<void> fuseMagic() => _play('sfx/fuse_magic.mp3');
}
