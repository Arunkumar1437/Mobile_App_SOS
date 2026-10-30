import 'package:flutter/material.dart';

import 'contacts_screen.dart';
import 'helplines_screen.dart';
import 'nearby_screen.dart';
import 'sos_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          SosScreen(onOpenContacts: () => setState(() => _index = 2)),
          const NearbyScreen(),
          const ContactsScreen(),
          const HelplinesScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.sos), label: 'SOS'),
          NavigationDestination(icon: Icon(Icons.near_me), label: 'Nearby'),
          NavigationDestination(icon: Icon(Icons.contacts), label: 'Contacts'),
          NavigationDestination(
              icon: Icon(Icons.phone_in_talk), label: 'Helplines'),
        ],
      ),
    );
  }
}
