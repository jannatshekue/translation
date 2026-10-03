import 'package:flutter/material.dart';

import '../../../../core/services/settings_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../communicate/presentation/screens/communicate_screen.dart';
import '../../../emergency_mode/presentation/screens/emergency_mode_screen.dart';
import '../../../home/presentation/screens/home_screen.dart';
import '../../../learning_module/presentation/screens/learning_module_screen.dart';

/// Lets any screen switch the main tab (e.g. Home's emergency strip jumps to
/// the Emergency tab) without owning the shell's state.
class ShellNavigation {
  ShellNavigation._();

  static const int home = 0;
  static const int communicate = 1;
  static const int learn = 2;
  static const int emergency = 3;

  static final ValueNotifier<int> tab = ValueNotifier<int>(home);

  static void goTo(int index) => tab.value = index;
}

/// The app's top-level structure: four destinations that never change, so
/// people always know where they are.
///
///  * Home — the one thing to do now, plus shortcuts.
///  * Communicate — every way of talking, grouped by situation.
///  * Learn — lessons and custom signs.
///  * Emergency — one-tap alert to the people you chose.
///
/// Individual tools (camera, captions, pairing…) open full-screen on top of
/// these tabs and return to them. Settings lives behind Home's profile button.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // Tabs are built the first time they're opened, then kept alive so
  // switching back is instant and preserves scroll position.
  final Set<int> _built = {ShellNavigation.home};

  @override
  void initState() {
    super.initState();
    ShellNavigation.tab.value = ShellNavigation.home;
    ShellNavigation.tab.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!mounted) return;
    setState(() => _built.add(ShellNavigation.tab.value));
  }

  @override
  void dispose() {
    ShellNavigation.tab.removeListener(_onTabChanged);
    super.dispose();
  }

  Widget _page(int index) {
    if (!_built.contains(index)) return const SizedBox.shrink();
    return switch (index) {
      ShellNavigation.home => const HomeScreen(),
      ShellNavigation.communicate => const CommunicateScreen(),
      ShellNavigation.learn => const LearningModuleScreen(),
      _ => const EmergencyModeScreen(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final selected = ShellNavigation.tab.value;

    return PopScope(
      // Back from any other tab returns to Home first; only Home exits.
      canPop: selected == ShellNavigation.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ShellNavigation.goTo(ShellNavigation.home);
      },
      child: Scaffold(
        body: IndexedStack(
          index: selected,
          children: [for (var i = 0; i < 4; i++) _page(i)],
        ),
        // The bar's labels keep their normal size whatever the text-size
        // setting: each tab gets only a quarter of the screen width, and at
        // large sizes a word like "Communicate" would break mid-word. The
        // icons carry the meaning, and every screen's own text still scales.
        bottomNavigationBar: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.0,
          child: NavigationBar(
            selectedIndex: selected,
            onDestinationSelected: (index) {
              SettingsService.instance.hapticTap();
              ShellNavigation.goTo(index);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.forum_outlined),
                selectedIcon: Icon(Icons.forum),
                label: 'Communicate',
              ),
              NavigationDestination(
                icon: Icon(Icons.school_outlined),
                selectedIcon: Icon(Icons.school),
                label: 'Learn',
              ),
              NavigationDestination(
                icon: Icon(Icons.emergency_outlined, color: AppTheme.emergency),
                selectedIcon: Icon(Icons.emergency, color: AppTheme.emergency),
                label: 'Emergency',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
