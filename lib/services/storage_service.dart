import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmergencyContact {
  const EmergencyContact({required this.name, required this.phone});

  final String name;
  final String phone;

  Map<String, String> toJson() => {'name': name, 'phone': phone};

  factory EmergencyContact.fromJson(Map<String, dynamic> j) =>
      EmergencyContact(name: j['name'] as String, phone: j['phone'] as String);
}

/// Saves emergency contacts and SOS settings on the device.
class StorageService {
  static const _kContacts = 'contacts';
  static const _kMessage = 'sos_message';
  static const _kInclude112 = 'include_112';

  static const defaultMessage =
      'EMERGENCY! I need help immediately. This is an SOS sent from my phone.';

  /// Bumped whenever settings change, so other screens can reload.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static Future<List<EmergencyContact>> loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kContacts);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => EmergencyContact.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveContacts(List<EmergencyContact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kContacts,
      jsonEncode(contacts.map((c) => c.toJson()).toList()),
    );
    changes.value++;
  }

  static Future<String> loadMessage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kMessage) ?? defaultMessage;
  }

  static Future<void> saveMessage(String message) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kMessage,
      message.trim().isEmpty ? defaultMessage : message.trim(),
    );
    changes.value++;
  }

  static Future<bool> loadInclude112() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kInclude112) ?? true;
  }

  static Future<void> saveInclude112(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kInclude112, value);
    changes.value++;
  }
}
