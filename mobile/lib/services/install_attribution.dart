import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Play's referrer is attribution evidence, never payment verification.
Map<String, String> parseInstallReferrer(String raw) {
  try {
    var query = raw.trim();
    if (!query.contains('=') && query.contains('%')) {
      query = Uri.decodeComponent(query);
    }
    if (query.startsWith('?')) query = query.substring(1);
    return Uri.splitQueryString(query);
  } on FormatException {
    return {};
  } on ArgumentError {
    return {};
  }
}

String classifyInstallReferrer(Map<String, String> params) {
  final source = (params['utm_source'] ?? '').toLowerCase();
  final medium = (params['utm_medium'] ?? '').toLowerCase();
  if (['meta', 'facebook', 'instagram', 'ig', 'fb'].contains(source)) return 'meta';
  if (medium == 'organic' || source == 'google-play' || source == 'organic') return 'organic';
  if (source == 'direct') return 'direct';
  return source.isEmpty ? 'unknown' : 'other';
}

class InstallAttribution {
  static const _channel = MethodChannel('app/install-referrer');
  static Future<Map<String, dynamic>> read(String apkFallback) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('install_referrer_v2');
    if (saved != null) {
      try { return Map<String, dynamic>.from(jsonDecode(saved) as Map); } catch (_) { /* retry */ }
    }
    Map<String, dynamic> native = {};
    try {
      native = Map<String, dynamic>.from(await _channel.invokeMapMethod<String, dynamic>('read').timeout(const Duration(seconds: 8)) ?? {});
    } catch (_) { /* Unavailable Play service must never block login. */ }
    final play = native['is_play'] == true;
    final raw = native['status'] == 'ok' ? '${native['referrer'] ?? ''}' : (!play ? apkFallback : '');
    final params = parseInstallReferrer(raw);
    final result = <String, dynamic>{
      'status': native['status'] == 'ok' ? 'play_referrer' : (!play && apkFallback.isNotEmpty ? 'apk_define' : 'unavailable'),
      'raw': raw,
      'params': params,
      'classification': classifyInstallReferrer(params),
      'click_timestamp': native['click_timestamp'],
      'install_timestamp': native['install_timestamp'],
      'installer': native['installer'],
    };
    // Cache a successful Play lookup or an explicit direct APK. Transient failures retry.
    if (native['status'] == 'ok' || (!play && native['status'] == 'not_play')) {
      await prefs.setString('install_referrer_v2', jsonEncode(result));
    }
    return result;
  }
}
