import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// Shown instead of everything else while the app is locked. Nothing behind
/// it is built, so no financial data is on screen or in the app switcher's
/// snapshot.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  @override
  void initState() {
    super.initState();
    // Ask straight away; the button is there if the user cancels.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.read(context).unlock();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [Expanded(child: Wordmark()), LanguageToggle(dense: true)]),
                  const SizedBox(height: Space.xxl),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(color: Palette.accentWash, shape: BoxShape.circle),
                    child: const Icon(Icons.fingerprint, size: 30, color: Palette.accent),
                  ),
                  const SizedBox(height: Space.lg),
                  Text(s.lockedTitle, style: Txt.title),
                  const SizedBox(height: Space.xs),
                  if (app.lockedUser != null) Text(s.welcomeBack(app.lockedUser!), style: Txt.body.copyWith(fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(s.lockedBody, style: Txt.bodyMuted),
                  const SizedBox(height: Space.xl),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: app.unlocking ? null : app.unlock,
                      icon: app.unlocking
                          ? const SizedBox(
                              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white))
                          : const Icon(Icons.fingerprint, size: 20),
                      label: Text(s.unlockWithFingerprint),
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Center(
                    child: TextButton(
                      onPressed: app.unlocking ? null : app.usePasswordInstead,
                      child: Text(s.usePasswordInstead),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One-time card after sign-in: "Unlock with your fingerprint next time?"
class BiometricOffer extends StatelessWidget {
  const BiometricOffer({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    if (!app.offerBiometric) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Notice(
          title: s.offerTitle,
          body: s.offerBody,
          tone: Palette.accent,
          wash: Palette.accentWash,
          icon: Icons.fingerprint,
          action: Wrap(spacing: Space.sm, children: [
            FilledButton(
              onPressed: () async {
                final err = await app.setBiometric(true);
                if (err != null && context.mounted) showMessage(context, err);
              },
              child: Text(s.turnOn),
            ),
            TextButton(onPressed: app.dismissBiometricOffer, child: Text(s.notNow)),
          ]),
        ),
      ),
    );
  }
}
