import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/place.dart';
import '../services/location_service.dart';
import '../services/places_service.dart';
import '../services/sos_service.dart';
import '../services/storage_service.dart';

enum SosStage { idle, countdown, working, done, failed }

class SosScreen extends StatefulWidget {
  const SosScreen({super.key, required this.onOpenContacts});

  final VoidCallback onOpenContacts;

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen>
    with SingleTickerProviderStateMixin {
  static const _countdownFrom = 5;
  static const _sosRed = Color(0xFFD32F2F);

  late final AnimationController _pulse;
  Timer? _timer;

  SosStage _stage = SosStage.idle;
  int _remaining = _countdownFrom;
  String _status = '';
  String? _error;

  Position? _position;
  bool _locating = false;
  LocationException? _locationError;

  List<Place> _police = [];
  bool _loadingPolice = false;

  List<EmergencyContact> _contacts = [];
  bool _include112 = true;
  bool _autoSend = false;
  String _baseMessage = StorageService.defaultMessage;

  // How the last SOS went out: texted straight from the phone, or handed to
  // the SMS app because auto-send was off, unavailable or failed.
  int _sentCount = 0;
  int _failedCount = 0;

  Place? get _nearestPolice => _police.isEmpty ? null : _police.first;

  Place? get _callablePolice {
    for (final p in _police) {
      if (p.phone != null) return p;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    StorageService.changes.addListener(_loadSettings);
    _loadSettings();
    _refreshLocation();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    StorageService.changes.removeListener(_loadSettings);
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final contacts = await StorageService.loadContacts();
    final include112 = await StorageService.loadInclude112();
    final autoSend = await StorageService.loadAutoSend();
    final message = await StorageService.loadMessage();
    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _include112 = include112;
      _autoSend = autoSend;
      _baseMessage = message;
    });
  }

  Future<void> _refreshLocation() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      final pos = await LocationService.getCurrent();
      if (!mounted) return;
      setState(() => _position = pos);
      unawaited(_loadPolice(pos));
    } on LocationException catch (e) {
      if (mounted) setState(() => _locationError = e);
    } catch (e) {
      if (mounted) {
        setState(() => _locationError = LocationException(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _loadPolice(Position pos) async {
    setState(() => _loadingPolice = true);
    try {
      final list = await PlacesService.search(
          PlaceCategory.police, pos.latitude, pos.longitude);
      if (mounted) setState(() => _police = list);
    } catch (_) {
      // Keep whatever we had; the SOS still works without it.
    } finally {
      if (mounted) setState(() => _loadingPolice = false);
    }
  }

  // ---------------------------------------------------------------- SOS flow

  void _startCountdown() {
    if (_stage == SosStage.countdown || _stage == SosStage.working) return;
    setState(() {
      _stage = SosStage.countdown;
      _remaining = _countdownFrom;
      _error = null;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_remaining <= 1) {
        t.cancel();
        _triggerSos();
      } else {
        setState(() => _remaining--);
      }
    });
  }

  void _cancelCountdown() {
    _timer?.cancel();
    setState(() => _stage = SosStage.idle);
  }

  Future<void> _triggerSos() async {
    _timer?.cancel();
    if (_stage == SosStage.working) return;
    setState(() {
      _stage = SosStage.working;
      _status = 'Getting your location…';
    });

    Position? pos;
    try {
      pos = await LocationService.getCurrent();
      _position = pos;
    } on LocationException catch (e) {
      _locationError = e;
      pos = _position ?? LocationService.lastPosition; // best we have
    } catch (_) {
      pos = _position ?? LocationService.lastPosition;
    }

    if (pos != null && mounted) {
      setState(() => _status = 'Finding nearest police station…');
      try {
        _police = await PlacesService.search(
                PlaceCategory.police, pos.latitude, pos.longitude)
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        // Send anyway; do not hold up the SOS.
      }
    }

    if (!mounted) return;
    setState(() => _status = _autoSend ? 'Sending SMS…' : 'Opening SMS…');
    final opened = await _deliver(pos);
    if (!mounted) return;
    setState(() {
      _stage = opened ? SosStage.done : SosStage.failed;
      _error = opened ? null : 'Could not send or open the SMS. Call 112 now.';
    });
  }

  List<String> get _recipients => [
        if (_include112) '112',
        ..._contacts.map((c) => c.phone),
      ];

  String _recipientSummary() {
    final parts = <String>[
      if (_include112) '112',
      if (_contacts.isNotEmpty)
        '${_contacts.length} contact${_contacts.length == 1 ? '' : 's'}',
    ];
    return parts.isEmpty ? '112' : parts.join(' + ');
  }

  /// Sends the SOS text. With auto-send on and the SMS permission granted it
  /// goes out straight from the phone. Anything that can't be sent that way
  /// (no permission, no signal) falls back to the SMS app, where the user taps
  /// Send. Returns false only if nothing could be sent or opened.
  Future<bool> _deliver(Position? pos) async {
    final msg = SosService.buildMessage(
      base: _baseMessage,
      position: pos,
      police: _nearestPolice,
    );
    void record(int sent, int failed) {
      if (!mounted) return;
      setState(() {
        _sentCount = sent;
        _failedCount = failed;
      });
    }

    var numbers = _recipients;
    var sent = 0;
    if (_autoSend) {
      final result = await SosService.sendSms(numbers, msg);
      if (result != null) {
        final failed = [
          for (final e in result.entries)
            if (!e.value) e.key,
        ];
        sent = result.length - failed.length;
        if (failed.isEmpty) {
          record(sent, 0);
          return true;
        }
        numbers = failed;
      }
    }
    record(sent, sent > 0 ? numbers.length : 0);
    return SosService.openSms(numbers, msg);
  }

  // ---------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AK SOS'),
        actions: [
          IconButton(
            tooltip: 'Refresh location',
            onPressed: _locating ? null : _refreshLocation,
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshLocation,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (_contacts.isEmpty)
              Card(
                color: theme.colorScheme.tertiaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.person_add_alt_1),
                  title: const Text('Add emergency contacts'),
                  subtitle: const Text(
                      'Family or friends who should get your SOS location.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.onOpenContacts,
                ),
              ),
            Center(child: _buildSosButton()),
            _buildStageArea(theme),
            const SizedBox(height: 20),
            _buildQuickCalls(),
            const SizedBox(height: 12),
            _buildPoliceCard(theme),
            const SizedBox(height: 12),
            _buildLocationCard(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildSosButton() {
    const size = 200.0;
    final busy = _stage == SosStage.working;
    return SizedBox(
      width: 290,
      height: 290,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) => Stack(
              alignment: Alignment.center,
              children: [
                for (var i = 0; i < 3; i++)
                  _ring((_pulse.value + i / 3) % 1.0, size),
              ],
            ),
          ),
          Material(
            color: _sosRed,
            shape: const CircleBorder(),
            elevation: 8,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: busy
                  ? null
                  : (_stage == SosStage.countdown
                      ? _triggerSos
                      : _startCountdown),
              onLongPress: busy ? null : _triggerSos,
              child: SizedBox(
                width: size,
                height: size,
                child: Center(child: _sosLabel()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring(double t, double size) {
    final d = size * (1 + t * 0.4);
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _sosRed.withAlpha(((1 - t) * 70).round()),
      ),
    );
  }

  Widget _sosLabel() {
    const white = Colors.white;
    switch (_stage) {
      case SosStage.countdown:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$_remaining',
                style: const TextStyle(
                    color: white, fontSize: 72, fontWeight: FontWeight.w800)),
            const Text('Tap to send now',
                style: TextStyle(color: white, fontSize: 14)),
          ],
        );
      case SosStage.working:
        return const SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(color: white, strokeWidth: 5),
        );
      case SosStage.idle:
      case SosStage.done:
      case SosStage.failed:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('SOS',
                style: TextStyle(
                    color: white,
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4)),
            Text('Tap, or hold to send instantly',
                style: TextStyle(color: white, fontSize: 12)),
          ],
        );
    }
  }

  Widget _buildStageArea(ThemeData theme) {
    switch (_stage) {
      case SosStage.idle:
        return Text(
          'Sends your live location to ${_recipientSummary()}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        );
      case SosStage.countdown:
        return Column(
          children: [
            Text('Sending SOS in $_remaining…',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _cancelCountdown,
              icon: const Icon(Icons.close),
              label: const Text('Cancel'),
            ),
          ],
        );
      case SosStage.working:
        return Text(_status,
            textAlign: TextAlign.center, style: theme.textTheme.titleMedium);
      case SosStage.done:
        final texted = _sentCount > 0;
        return _ResultCard(
          icon: Icons.check_circle,
          color: Colors.green,
          title: texted && _failedCount == 0 ? 'SOS sent' : 'SOS message ready',
          body: !texted
              ? 'Your SMS app opened with your location for '
                  '${_recipientSummary()}. Tap Send there if it has not gone '
                  'yet, then call for help below.'
              : _failedCount == 0
                  ? 'Your location was texted to ${_recipientSummary()}. '
                      'Now call for help below.'
                  : 'Texted $_sentCount of ${_sentCount + _failedCount} '
                      'numbers. Your SMS app opened for the rest: tap Send '
                      'there, then call for help below.',
          onResend: () => _deliver(_position),
          onDone: () => setState(() => _stage = SosStage.idle),
        );
      case SosStage.failed:
        return _ResultCard(
          icon: Icons.error,
          color: theme.colorScheme.error,
          title: 'Could not send SOS',
          body: _error ?? 'Something went wrong. Call 112 now.',
          onResend: () => _deliver(_position),
          onDone: () => setState(() => _stage = SosStage.idle),
        );
    }
  }

  Widget _buildQuickCalls() {
    final police = _callablePolice;
    return Row(
      children: [
        const Expanded(
          child: _CallTile(
              label: 'Emergency',
              number: '112',
              icon: Icons.emergency,
              color: _sosRed),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: _CallTile(
              label: 'Ambulance',
              number: '108',
              icon: Icons.local_hospital,
              color: Color(0xFF2E7D32)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CallTile(
            label: 'Police stn',
            number: police?.phone,
            icon: Icons.local_police,
            color: PlaceCategory.police.color,
            fallback: _loadingPolice ? 'Searching…' : 'No number',
          ),
        ),
      ],
    );
  }

  Widget _buildPoliceCard(ThemeData theme) {
    final p = _nearestPolice;
    final callable = _callablePolice;
    final Widget content;

    if (p == null) {
      content = ListTile(
        leading: _loadingPolice
            ? const SizedBox(
                width: 24, height: 24, child: CircularProgressIndicator())
            : const Icon(Icons.local_police),
        title: Text(_loadingPolice
            ? 'Finding nearest police station…'
            : (_position == null
                ? 'Waiting for your location'
                : 'No police station found on the map nearby. Call 112.')),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: PlaceCategory.police.color,
              foregroundColor: Colors.white,
              child: const Icon(Icons.local_police),
            ),
            title: Text(p.name),
            subtitle: Text([
              '${p.distanceLabel} away',
              if (p.address != null) p.address!,
              if (p.phone != null) 'Ph: ${p.phone}',
            ].join('\n')),
            isThreeLine: p.address != null || p.phone != null,
          ),
          if (p.phone == null && callable != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'No phone listed here. Nearest station with a phone: '
                '${callable.name} (${callable.distanceLabel}).',
                style: theme.textTheme.bodySmall,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (callable != null)
                  FilledButton.icon(
                    onPressed: () => SosService.call(callable.phone!),
                    icon: const Icon(Icons.call),
                    label: Text(p.phone != null ? 'Call' : 'Call nearest'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => SosService.directions(p.lat, p.lon),
                  icon: const Icon(Icons.directions),
                  label: const Text('Directions'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('NEAREST POLICE STATION',
                style: theme.textTheme.labelMedium),
          ),
          content,
        ],
      ),
    );
  }

  Widget _buildLocationCard(ThemeData theme) {
    final err = _locationError;
    final pos = _position;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('YOUR LOCATION', style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            if (_locating && pos == null)
              const Text('Getting GPS fix…')
            else if (pos != null)
              Text(
                '${pos.latitude.toStringAsFixed(5)}, '
                '${pos.longitude.toStringAsFixed(5)}  '
                '(±${pos.accuracy.round()} m)',
                style: theme.textTheme.bodyLarge,
              ),
            if (err != null) ...[
              const SizedBox(height: 8),
              Text(err.message,
                  style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                      onPressed: _refreshLocation,
                      child: const Text('Try again')),
                  if (err.fix != LocationFix.none)
                    FilledButton.tonal(
                      onPressed: () => LocationService.applyFix(err.fix),
                      child: const Text('Open settings'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({
    required this.label,
    required this.number,
    required this.icon,
    required this.color,
    this.fallback = '',
  });

  final String label;
  final String? number;
  final IconData icon;
  final Color color;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final enabled = number != null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? () => SosService.call(number!) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(
            children: [
              Icon(icon, color: enabled ? color : Colors.grey, size: 30),
              const SizedBox(height: 6),
              Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
              Text(
                enabled ? number! : fallback,
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.onResend,
    required this.onDone,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final VoidCallback onResend;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 6),
            Text(body),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onResend, child: const Text('Send again')),
                TextButton(onPressed: onDone, child: const Text('Done')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
