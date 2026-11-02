import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/place.dart';

/// Builds the SOS text and hands off to the phone's SMS app, dialer and maps.
class SosService {
  /// Android-only channel (see MainActivity.kt) that texts without the SMS app.
  static const _sms = MethodChannel('com.example.suraksha_sos/sms');

  static String buildMessage({
    required String base,
    Position? position,
    Place? police,
  }) {
    final b = StringBuffer(base.trim());
    b.writeln();
    if (position != null) {
      final lat = position.latitude.toStringAsFixed(6);
      final lon = position.longitude.toStringAsFixed(6);
      b.writeln('My location: https://maps.google.com/?q=$lat,$lon');
      b.writeln('GPS: $lat, $lon (+/-${position.accuracy.round()} m)');
    } else {
      b.writeln('My location: unavailable (GPS off or no signal)');
    }
    if (police != null) {
      final phone = police.phone == null ? '' : ', ph ${police.phone}';
      b.writeln(
          'Nearest police: ${police.name} (${police.distanceLabel})$phone');
    }
    b.write('Sent: ${_timestamp(DateTime.now())}');
    return b.toString();
  }

  /// Only Android can text without opening the SMS app, and only once the
  /// user grants the SMS permission (see [requestSmsPermission]).
  static bool get autoSendSupported => Platform.isAndroid;

  static Future<bool> hasSmsPermission() async {
    if (!autoSendSupported) return false;
    try {
      return await _sms.invokeMethod<bool>('hasPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Shows Android's SMS permission prompt. True if it is granted.
  static Future<bool> requestSmsPermission() async {
    if (!autoSendSupported) return false;
    try {
      return await _sms.invokeMethod<bool>('requestPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Texts [body] to every number straight from the phone, with no SMS app and
  /// no tap on Send. Returns, per number, whether the phone's radio accepted
  /// it. Null means auto-send is not available (not Android, or no SMS
  /// permission): nothing was sent, so fall back to [openSms].
  static Future<Map<String, bool>?> sendSms(
    List<String> numbers,
    String body,
  ) async {
    if (!await hasSmsPermission()) return null;
    try {
      return await _sms.invokeMapMethod<String, bool>(
        'send',
        {'numbers': _recipients(numbers), 'body': body},
      );
    } catch (_) {
      return null;
    }
  }

  /// Opens the SMS app with all recipients and the message filled in.
  /// The user taps Send (see README for why this is the default).
  static Future<bool> openSms(List<String> numbers, String body) async {
    final nums = _recipients(numbers);
    final encoded = Uri.encodeComponent(body);

    final Uri uri;
    if (Platform.isIOS) {
      uri = nums.length > 1
          ? Uri.parse('sms://open?addresses=${nums.join(',')}&body=$encoded')
          : Uri.parse('sms:${nums.first}&body=$encoded');
    } else {
      uri = Uri.parse('sms:${nums.join(';')}?body=$encoded');
    }
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> call(String number) async {
    final n = cleanPhone(number);
    if (n.isEmpty) return false;
    try {
      return await launchUrl(Uri(scheme: 'tel', path: n));
    } catch (_) {
      return false;
    }
  }

  static Future<bool> directions(double lat, double lon) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon');
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static String cleanPhone(String p) => p.replaceAll(RegExp(r'[^0-9+]'), '');

  /// Cleaned, de-duplicated numbers; 112 if there are none.
  static List<String> _recipients(List<String> numbers) {
    final nums = numbers
        .map(cleanPhone)
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();
    if (nums.isEmpty) nums.add('112');
    return nums;
  }

  static String _timestamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
  }
}
