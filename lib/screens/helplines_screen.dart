import 'package:flutter/material.dart';

import '../services/sos_service.dart';

class Helpline {
  const Helpline(this.name, this.number, this.icon, this.note);
  final String name;
  final String number;
  final IconData icon;
  final String note;
}

/// National helplines in India. Some states run extra local numbers;
/// verify for your state before release.
const helplines = <Helpline>[
  Helpline('National Emergency', '112', Icons.emergency,
      'Police, fire, ambulance — call or SMS'),
  Helpline('Police', '100', Icons.local_police, 'Routed to 112 in most states'),
  Helpline('Fire', '101', Icons.fire_truck, 'Fire & rescue'),
  Helpline('Ambulance', '108', Icons.local_hospital, 'Emergency ambulance'),
  Helpline('Ambulance (alt.)', '102', Icons.airport_shuttle,
      'Patient transport / mother & child'),
  Helpline('Women Helpline', '1091', Icons.woman, 'Women in distress'),
  Helpline('Women Helpline (Domestic)', '181', Icons.support_agent,
      'Violence against women, 24x7'),
  Helpline('Child Helpline', '1098', Icons.child_care, 'Children in need'),
  Helpline('Railway Helpline (Rail Madad)', '139', Icons.train,
      'Security, medical & complaints on trains'),
  Helpline('Cyber Crime', '1930', Icons.security, 'Online fraud, report fast'),
  Helpline('Highway Emergency (NHAI)', '1033', Icons.add_road,
      'Accidents on national highways'),
  Helpline('Senior Citizens', '14567', Icons.elderly, 'Elder helpline'),
  Helpline('Mental Health (Tele-MANAS)', '14416', Icons.psychology,
      'Free 24x7 counselling'),
];

class HelplinesScreen extends StatelessWidget {
  const HelplinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Helplines (India)')),
      body: ListView.separated(
        itemCount: helplines.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, i) {
          final h = helplines[i];
          return ListTile(
            leading: CircleAvatar(child: Icon(h.icon)),
            title: Text(h.name),
            subtitle: Text(h.note),
            trailing: FilledButton.tonalIcon(
              onPressed: () => SosService.call(h.number),
              icon: const Icon(Icons.call, size: 18),
              label: Text(h.number),
            ),
            onTap: () => SosService.call(h.number),
          );
        },
      ),
    );
  }
}
