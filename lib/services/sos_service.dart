import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/place.dart';

/// Builds the SOS text and hands off to the phone's SMS app, dialer and maps.
class SosService {
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

  /// Opens the SMS app with all recipients and the message filled in.
  /// The user taps Send (see README for why the app does not auto-send).
  static Future<bool> openSms(List<String> numbers, String body) async {
    final nums = numbers
        .map(cleanPhone)
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();
    if (nums.isEmpty) nums.add('112');
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

  static String _timestamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
  }
}
