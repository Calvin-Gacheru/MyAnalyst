import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_controller.dart';
import '../theme/tokens.dart';
import 'common.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _create = false;
  bool _showPass = false;

  static final _userPattern = RegExp(r'^[A-Za-z0-9_.@-]{3,64}$');

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    AppScope.read(context).signIn(_user.text, _pass.text, create: _create);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final compact = isCompact(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: compact ? Space.md : Space.xxl, vertical: Space.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(children: [Expanded(child: Wordmark()), LanguageToggle(dense: true)]),
                      const SizedBox(height: Space.xxl),
                      Text(s.authTitle, style: Txt.title.copyWith(fontSize: compact ? 28 : 32)),
                      const SizedBox(height: Space.sm),
                      Text(s.authLead, style: Txt.bodyMuted.copyWith(fontSize: 15)),
                      const SizedBox(height: Space.xl),
                      Text(s.username, style: Txt.label),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _user,
                        enabled: !app.authBusy,
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        enableSuggestions: false,
                        inputFormatters: [LengthLimitingTextInputFormatter(64)],
                        decoration: InputDecoration(hintText: s.usernameRule),
                        validator: (v) => _userPattern.hasMatch((v ?? '').trim()) ? null : s.usernameInvalid,
                      ),
                      const SizedBox(height: Space.md),
                      Text(s.password, style: Txt.label),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _pass,
                        enabled: !app.authBusy,
                        obscureText: !_showPass,
                        autofillHints: [_create ? AutofillHints.newPassword : AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        autocorrect: false,
                        enableSuggestions: false,
                        inputFormatters: [LengthLimitingTextInputFormatter(128)],
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          hintText: s.passwordRule,
                          suffixIcon: IconButton(
                            tooltip: _showPass ? (s.zh ? '隐藏密码' : 'Hide password') : (s.zh ? '显示密码' : 'Show password'),
                            onPressed: () => setState(() => _showPass = !_showPass),
                            icon: Icon(_showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                size: 18, color: Palette.inkMuted),
                          ),
                        ),
                        validator: (v) => (v ?? '').length >= 8 ? null : s.passwordTooShort,
                      ),
                      if (app.lockBroken) ...[
                        const SizedBox(height: Space.md),
                        Notice(title: s.fingerprintUnlock, body: s.lockBrokenBody, icon: Icons.fingerprint,
                            tone: Palette.amber, wash: Palette.amberWash),
                      ],
                      if (app.authError != null) ...[
                        const SizedBox(height: Space.md),
                        Notice(title: s.failure(app.authError!), body: '', icon: Icons.error_outline),
                      ],
                      const SizedBox(height: Space.lg),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: app.authBusy ? null : _submit,
                          child: app.authBusy
                              ? const SizedBox(
                                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white))
                              : Text(_create ? s.createAccount : s.signIn),
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      Center(
                        child: TextButton(
                          onPressed: app.authBusy ? null : () => setState(() => _create = !_create),
                          child: Text(_create ? s.haveAccount : s.noAccount),
                        ),
                      ),
                      const SizedBox(height: Space.lg),
                      const Divider(),
                      const SizedBox(height: Space.md),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(Icons.lock_outline, size: 15, color: Palette.inkFaint),
                        ),
                        const SizedBox(width: Space.xs),
                        Expanded(
                          child: Text(app.isDemo ? '${s.demoSignInNote} ${s.securityNote}' : s.securityNote,
                              style: Txt.caption),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
