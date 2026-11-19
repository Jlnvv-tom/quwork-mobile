import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../auth/quwork_login_page.dart';

/// Compatibility route for upstream links that used to open a DeepSeek API
/// key form. QuWork is the only account and model-billing system now.
class ApiKeyPage extends StatelessWidget {
  const ApiKeyPage({super.key, this.onDone, this.onboarding = true, this.onBack});

  final VoidCallback? onDone;
  final bool onboarding;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => QuWorkLoginPage(
    embedded: onboarding,
    onDone: onDone ?? onBack,
  );
}

/// Kept for source compatibility with upstream tests and integrations. The
/// product no longer accepts a standalone provider key.
String normalizeApiKey(String raw) => raw.replaceAll(RegExp(r'\s'), '');

String? apiKeyWarning(String key) => key.isEmpty ? null : appL10n.quworkLoginTitle;

String maskApiKey(String key) => key.trim().isEmpty ? '' : '••••';
