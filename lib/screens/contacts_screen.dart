import 'package:flutter/material.dart';

import '../services/sos_service.dart';
import '../services/storage_service.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<EmergencyContact> _contacts = [];
  bool _include112 = true;
  final _messageCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final contacts = await StorageService.loadContacts();
    final include112 = await StorageService.loadInclude112();
    final message = await StorageService.loadMessage();
    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _include112 = include112;
      _messageCtrl.text = message;
    });
  }

  Future<void> _addContact() async {
    final result = await showDialog<EmergencyContact>(
      context: context,
      builder: (_) => const _AddContactDialog(),
    );
    if (result == null) return;
    final updated = [..._contacts, result];
    await StorageService.saveContacts(updated);
    setState(() => _contacts = updated);
  }

  Future<void> _remove(int i) async {
    final updated = [..._contacts]..removeAt(i);
    await StorageService.saveContacts(updated);
    setState(() => _contacts = updated);
  }

  Future<void> _saveMessage() async {
    await StorageService.saveMessage(_messageCtrl.text);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('SOS message saved')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency contacts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addContact,
        icon: const Icon(Icons.person_add),
        label: const Text('Add contact'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          if (_contacts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No contacts yet. Add family or friends who should receive '
                'your SOS message with your live location.',
                textAlign: TextAlign.center,
              ),
            ),
          for (var i = 0; i < _contacts.length; i++)
            ListTile(
              leading: CircleAvatar(
                child: Text(_contacts[i].name.isEmpty
                    ? '?'
                    : _contacts[i].name[0].toUpperCase()),
              ),
              title: Text(_contacts[i].name),
              subtitle: Text(_contacts[i].phone),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Call',
                    icon: const Icon(Icons.call),
                    onPressed: () => SosService.call(_contacts[i].phone),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _remove(i),
                  ),
                ],
              ),
            ),
          const Divider(height: 32),
          SwitchListTile(
            title: const Text('Include 112 in SOS SMS'),
            subtitle: const Text(
                "India's national emergency number. Turn off while testing "
                'so you do not send false alarms.'),
            value: _include112,
            onChanged: (v) async {
              setState(() => _include112 = v);
              await StorageService.saveInclude112(v);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text('SOS MESSAGE', style: theme.textTheme.labelMedium),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _messageCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                helperText:
                    'Your location link, nearest police station and time are '
                    'added automatically.',
                helperMaxLines: 2,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saveMessage,
                child: const Text('Save message'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddContactDialog extends StatefulWidget {
  const _AddContactDialog();

  @override
  State<_AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<_AddContactDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(EmergencyContact(
      name: _name.text.trim(),
      phone: SosService.cleanPhone(_phone.text),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add emergency contact'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile number',
                hintText: '+91 98765 43210',
              ),
              validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                return digits.length < 10 ? 'Enter a valid mobile number' : null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
