import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../l10n/l10n.dart';

/// Aliyun CAPTCHA 2.0 (slider) settings.
///
/// This is the same scene Qurvis uses on desktop: the account service checks the
/// `aliyun_captcha` query parameter with the base64 `captchaVerifyParam` the Web
/// SDK returns, so the values must match `Qurvis/config/app.config.js`.
@immutable
class AliyunCaptchaSettings {
  const AliyunCaptchaSettings({
    required this.region,
    required this.prefix,
    required this.sceneId,
  });

  final String region;
  final String prefix;
  final String sceneId;

  /// Overridable for other environments; the defaults are Qurvis's production
  /// scene, which the mobile login talks to.
  static const AliyunCaptchaSettings defaults = AliyunCaptchaSettings(
    region: String.fromEnvironment('QUWORK_CAPTCHA_REGION', defaultValue: 'cn'),
    prefix: String.fromEnvironment('QUWORK_CAPTCHA_PREFIX', defaultValue: '1hms8d'),
    sceneId: String.fromEnvironment('QUWORK_CAPTCHA_SCENE_ID', defaultValue: '10vzkucv'),
  );

  /// Qurvis treats a missing piece as "captcha disabled" instead of failing
  /// every send-code request.
  bool get enabled => region.isNotEmpty && prefix.isNotEmpty && sceneId.isNotEmpty;
}

/// How a slider challenge ended.
sealed class AliyunCaptchaOutcome {
  const AliyunCaptchaOutcome();
}

/// The challenge passed; [param] is Aliyun's `captchaVerifyParam`.
final class AliyunCaptchaPassed extends AliyunCaptchaOutcome {
  const AliyunCaptchaPassed(this.param);

  final String param;
}

/// The user closed the popup. Like Qurvis, this is silent: the next tap on
/// "Send code" starts a fresh challenge.
final class AliyunCaptchaDismissed extends AliyunCaptchaOutcome {
  const AliyunCaptchaDismissed();
}

/// The SDK failed to load, errored, or the challenge timed out.
final class AliyunCaptchaFailed extends AliyunCaptchaOutcome {
  const AliyunCaptchaFailed(this.message);

  final String message;
}

/// Shows the slider and resolves with the outcome. Never resolves to `null`.
Future<AliyunCaptchaOutcome> showAliyunCaptcha(
  BuildContext context, {
  AliyunCaptchaSettings settings = AliyunCaptchaSettings.defaults,
}) async {
  final outcome = await showDialog<AliyunCaptchaOutcome>(
    context: context,
    barrierDismissible: false,
    barrierColor: const Color(0x99000000),
    useSafeArea: false,
    builder: (_) => AliyunCaptchaChallenge(settings: settings),
  );
  return outcome ?? const AliyunCaptchaDismissed();
}

/// Full-screen WebView hosting `assets/aliyun_captcha/index.html`.
///
/// Every challenge gets a fresh page, which is what Qurvis emulates on desktop
/// by reloading the SDK script: the Aliyun SDK does not reset after one run.
class AliyunCaptchaChallenge extends StatefulWidget {
  const AliyunCaptchaChallenge({super.key, required this.settings});

  final AliyunCaptchaSettings settings;

  @override
  State<AliyunCaptchaChallenge> createState() => _AliyunCaptchaChallengeState();
}

class _AliyunCaptchaChallengeState extends State<AliyunCaptchaChallenge> {
  static const _pageAsset = 'assets/aliyun_captcha/index.html';
  static const _bridge = 'AliyunCaptchaBridge';

  /// `initAliyunCaptcha` only registers; the SDK finishes asynchronously and the
  /// hidden trigger does nothing until then. Qurvis waits for `getInstance` with
  /// this same fallback so a missed callback cannot hang the dialog.
  static const _readyFallback = Duration(milliseconds: 1500);
  static const _idleTimeout = Duration(seconds: 60);

  late final WebViewController _controller;
  Timer? _readyTimer;
  Timer? _idleTimer;
  bool _triggered = false;
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(_bridge, onMessageReceived: _onMessage)
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: (_) => unawaited(_start())))
      ..setOnConsoleMessage((message) {
        if (kDebugMode) debugPrint('[aliyun-captcha] console ${message.message}');
      });
    unawaited(_controller.loadFlutterAsset(_pageAsset));
    _idleTimer = Timer(_idleTimeout, () {
      if (mounted) _settle(AliyunCaptchaFailed(context.l10n.quworkCaptchaTimeout));
    });
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    _idleTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (_settled) return;
    final settings = widget.settings;
    final language = Localizations.localeOf(context).languageCode == 'zh' ? 'cn' : 'en';
    final config = jsonEncode({
      'region': settings.region,
      'prefix': settings.prefix,
      'sceneId': settings.sceneId,
      'language': language,
    });
    try {
      await _controller.runJavaScript('window.startCaptcha($config);');
    } on Object {
      if (mounted) _settle(AliyunCaptchaFailed(context.l10n.quworkCaptchaFailed));
      return;
    }
    if (_settled) return;
    _readyTimer?.cancel();
    _readyTimer = Timer(_readyFallback, _trigger);
  }

  void _trigger({bool force = false}) {
    if (_settled) return;
    if (_triggered && !force) return;
    _triggered = true;
    if (mounted) setState(() {});
    unawaited(_controller.runJavaScript('window.triggerCaptcha();').catchError((_) {}));
  }

  void _onMessage(JavaScriptMessage message) {
    final decoded = jsonDecode(message.message);
    if (decoded is! Map<String, dynamic>) return;
    if (kDebugMode) {
      final value = decoded['value'];
      debugPrint(
        '[aliyun-captcha] message type=${decoded['type']} '
        'valueLen=${value is String ? value.length : 0}',
      );
    }
    switch (decoded['type']) {
      case 'ready':
        // The fallback click below can land before the SDK finishes wiring the
        // popup, so a late `ready` still gets to trigger a second time.
        _readyTimer?.cancel();
        _trigger(force: true);
      case 'success':
        final value = decoded['value'];
        if (value is String && value.isNotEmpty) {
          _settle(AliyunCaptchaPassed(value));
        } else if (mounted) {
          _settle(AliyunCaptchaFailed(context.l10n.quworkCaptchaFailed));
        }
      case 'fail':
        _settle(const AliyunCaptchaDismissed());
      case 'error':
        if (mounted) _settle(AliyunCaptchaFailed(context.l10n.quworkCaptchaFailed));
    }
  }

  void _settle(AliyunCaptchaOutcome outcome) {
    if (_settled) return;
    _settled = true;
    _readyTimer?.cancel();
    _idleTimer?.cancel();
    if (!mounted) return;
    Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(child: WebViewWidget(controller: _controller)),
            if (!_triggered)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
                            const SizedBox(height: 14),
                            Text(context.l10n.quworkCaptchaHint),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 8,
              child: IconButton.filledTonal(
                onPressed: () => _settle(const AliyunCaptchaDismissed()),
                icon: const Icon(Icons.close),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
