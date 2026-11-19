import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n.dart';
import '../../state/quwork_auth_state.dart';
import '../shell/page_frame.dart';
import 'aliyun_captcha.dart';

/// The WeChat entry stays hidden on mobile.
///
/// `/api/oauth/wechat/url` hands back an `open.weixin.qq.com/connect/qrconnect`
/// page — PC website authorisation, opened in the system browser, whose callback
/// the user has to copy and paste back. A phone app has to authorise inside the
/// WeChat App (`snsapi_userinfo` with an App-scheme callback) instead, so the
/// button and its paste field are off until that flow exists. Kept behind a
/// define so the desktop-shaped flow can still be exercised.
const bool _wechatLoginAvailable = bool.fromEnvironment('QUWORK_WECHAT_LOGIN');

class QuWorkLoginPage extends ConsumerStatefulWidget {
  const QuWorkLoginPage({super.key, this.embedded = false, this.onDone});

  /// The startup gate owns this page while the account is signed out. Once
  /// login succeeds the gate replaces it with the normal app shell.
  final bool embedded;
  final VoidCallback? onDone;

  @override
  ConsumerState<QuWorkLoginPage> createState() => _QuWorkLoginPageState();
}

class _QuWorkLoginPageState extends ConsumerState<QuWorkLoginPage> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _wechatCallback = TextEditingController();
  Timer? _timer;
  int _remaining = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    _wechatCallback.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phone.text.trim();
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      _show(context.l10n.quworkLoginPhoneInvalid);
      return;
    }
    // The account service reads the slider ticket from the `aliyun_captcha`
    // query parameter, so the challenge runs right before the code request.
    String? ticket;
    if (AliyunCaptchaSettings.defaults.enabled) {
      final outcome = await showAliyunCaptcha(context);
      if (!mounted) return;
      switch (outcome) {
        case AliyunCaptchaDismissed():
          return;
        case AliyunCaptchaFailed(:final message):
          _show(message);
          return;
        case AliyunCaptchaPassed(:final param):
          ticket = param;
      }
    }
    final result = await ref.read(quWorkAuthProvider.notifier).sendCode(phone, captcha: ticket);
    if (!mounted || result == null) return;
    _show(result.message.isEmpty ? context.l10n.quworkLoginCodeSent : result.message);
    _timer?.cancel();
    setState(() => _remaining = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _remaining <= 1) {
        timer.cancel();
        if (mounted) setState(() => _remaining = 0);
      } else {
        setState(() => _remaining--);
      }
    });
  }

  Future<void> _login() async {
    final phone = _phone.text.trim();
    final code = _code.text.trim();
    if (!RegExp(r'^1\d{10}$').hasMatch(phone) || !RegExp(r'^\d{4,8}$').hasMatch(code)) {
      _show(context.l10n.quworkLoginFieldsInvalid);
      return;
    }
    final auth = ref.read(quWorkAuthProvider);
    final ok = await ref.read(quWorkAuthProvider.notifier).login(phone, code, wechatToken: auth.wechatBindingToken);
    if (mounted && ok) {
      widget.onDone?.call();
      if (!widget.embedded) Navigator.of(context).pop();
    }
  }

  Future<void> _wechatLogin() async {
    final start = await ref.read(quWorkAuthProvider.notifier).startWechatLogin();
    if (!mounted || start == null) return;
    await launchUrl(start.url, mode: LaunchMode.externalApplication);
    if (mounted) _show(context.l10n.quworkWechatOpened);
  }

  Future<void> _finishWechatCallback() async {
    final uri = Uri.tryParse(_wechatCallback.text.trim());
    if (uri == null) {
      _show(context.l10n.quworkWechatCallbackInvalid);
      return;
    }
    await ref.read(quWorkAuthProvider.notifier).finishWechatCallback(uri);
  }

  void _show(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(quWorkAuthProvider);
    final error = auth.error?.message;
    if (auth.signedIn && auth.hasModelCredential) {
      return AppPage.list(
        title: context.l10n.quworkLoginTitle,
        children: [
          SettingsSectionLike(child: Text(auth.user!.label)),
          SettingsSectionLike(child: Text(context.l10n.quworkLoginSignedIn)),
          SettingsSectionLike(child: Text(context.l10n.quworkUsageSummary)),
          SettingsSectionLike(
            child: FilledButton.tonal(
              onPressed: auth.busy ? null : () => ref.read(quWorkAuthProvider.notifier).signOut(),
              child: Text(context.l10n.quworkLoginSignOut),
            ),
          ),
        ],
      );
    }
    if (auth.signedIn && !auth.hasModelCredential) {
      return AppPage.list(
        title: context.l10n.quworkLoginTitle,
        children: [
          SettingsSectionLike(child: Text(auth.user!.label)),
          SettingsSectionLike(child: Text(context.l10n.quworkLoginFailed)),
          SettingsSectionLike(child: Text(context.l10n.quworkUsageSummary)),
        ],
      );
    }
    return AppPage.list(
      title: context.l10n.quworkLoginTitle,
      children: [
        SettingsSectionLike(child: Text(context.l10n.quworkLoginIntro)),
        SettingsSectionLike(
          child: TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: context.l10n.quworkLoginPhone),
          ),
        ),
        SettingsSectionLike(
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: context.l10n.quworkLoginCode),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: auth.busy || _remaining > 0 ? null : _sendCode,
                child: Text(_remaining > 0 ? '${_remaining}s' : context.l10n.quworkLoginSendCode),
              ),
            ],
          ),
        ),
        if (error != null)
          SettingsSectionLike(
            child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        SettingsSectionLike(
          child: FilledButton(
            onPressed: auth.busy ? null : _login,
            child: Text(auth.busy ? context.l10n.quworkLoginWorking : context.l10n.quworkLoginSubmit),
          ),
        ),
        if (_wechatLoginAvailable) ...[
          SettingsSectionLike(
            child: OutlinedButton.icon(
              onPressed: auth.busy ? null : _wechatLogin,
              icon: const Icon(Icons.chat_bubble_outline),
              label: Text(context.l10n.quworkWechatLogin),
            ),
          ),
          if (auth.phase == QuWorkAuthPhase.wechatBindingRequired || auth.error?.code == 'wechat_bind_required')
            SettingsSectionLike(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(context.l10n.quworkWechatBindRequired),
                  TextField(
                    controller: _wechatCallback,
                    decoration: InputDecoration(labelText: context.l10n.quworkWechatCallback),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: _finishWechatCallback, child: Text(context.l10n.quworkWechatFinish)),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class SettingsSectionLike extends StatelessWidget {
  const SettingsSectionLike({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: child);
}
