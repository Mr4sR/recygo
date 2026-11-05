import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const MainShell({super.key, required this.navigationShell});

  void _go(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final useBottomBar = width < 720;
    final extendedRail = width >= 1100;
    final index = navigationShell.currentIndex;

    final destinations =
        <({IconData icon, IconData selectedIcon, String label})>[
          (icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
          (
            icon: Icons.inventory_2_outlined,
            selectedIcon: Icons.inventory_2,
            label: 'Collection',
          ),
          (
            icon: Icons.auto_awesome_outlined,
            selectedIcon: Icons.auto_awesome,
            label: 'Fuse',
          ),
          (
            icon: Icons.people_outline,
            selectedIcon: Icons.people,
            label: 'Community',
          ),
          (icon: Icons.map_outlined, selectedIcon: Icons.map, label: 'Explore'),
        ];

    Widget content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: navigationShell,
      ),
    );

    if (useBottomBar) {
      return Scaffold(
        body: content,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: _go,
          destinations: [
            for (int i = 0; i < destinations.length; i++)
              NavigationDestination(
                icon: i == 2
                    ? _FuseIcon(selected: index == 2)
                    : Icon(destinations[i].icon),
                selectedIcon: i == 2
                    ? _FuseIcon(selected: true)
                    : Icon(destinations[i].selectedIcon),
                label: destinations[i].label,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: extendedRail,
            selectedIndex: index,
            onDestinationSelected: _go,
            labelType: extendedRail
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Icon(Icons.recycling, color: Color(0xFF1B9E6B), size: 30),
            ),
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _FuseIcon extends StatelessWidget {
  final bool selected;
  const _FuseIcon({required this.selected});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF1B9E6B) : const Color(0xFFE6F7EE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Icon(
        Icons.auto_awesome,
        size: 20,
        color: selected ? Colors.white : const Color(0xFF0E6B45),
      ),
    );
  }
}
