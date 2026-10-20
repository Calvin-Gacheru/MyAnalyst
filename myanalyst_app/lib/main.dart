import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'data/http_repository.dart';
import 'data/mock_repository.dart';
import 'data/repository.dart';
import 'i18n/strings.dart';
import 'security/app_lock.dart';
import 'state/app_controller.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'ui/auth_screen.dart';
import 'ui/lock_screen.dart';
import 'ui/start_screen.dart';
import 'ui/workspace.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final AnalystRepository repo = AppConfig.useMock ? MockAnalystRepository() : HttpAnalystRepository();
  // Start in Chinese when the phone is set to Chinese.
  final zh = PlatformDispatcher.instance.locale.languageCode == 'zh';
  final controller = AppController(
    repo,
    isDemo: AppConfig.useMock,
    language: zh ? AppLanguage.zh : AppLanguage.en,
    lock: kIsWeb ? const NoAppLock() : BiometricAppLock(),
  );
  controller.restore();
  runApp(MyAnalystApp(controller: controller));
}

class MyAnalystApp extends StatelessWidget {
  const MyAnalystApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: MaterialApp(
        title: 'MyAnalyst',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

/// Watches the app lifecycle so the biometric lock can re-engage after
/// [AppController.relockAfter] in the background.
class _RootState extends State<_Root> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final app = AppScope.read(context);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) app.onBackgrounded();
    if (state == AppLifecycleState.resumed) app.onForegrounded();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final Widget child;
    if (app.restoring) {
      child = const Scaffold(
        key: ValueKey('restoring'),
        body: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 1.8, color: Palette.accent))),
      );
    } else if (app.locked) {
      child = const LockScreen(key: ValueKey('locked'));
    } else if (!app.signedIn) {
      child = const AuthScreen(key: ValueKey('auth'));
    } else if (app.dataset == null) {
      child = const StartScreen(key: ValueKey('start'));
    } else {
      child = WorkspaceShell(key: ValueKey(app.dataset!.id));
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: child);
  }
}
