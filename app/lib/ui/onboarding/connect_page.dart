import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/quwork_login_page.dart';

/// Compatibility wrapper for the upstream onboarding route.
///
/// QuWork owns the only account and model credential in the product build.
class ConnectPage extends ConsumerWidget {
  const ConnectPage({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) => QuWorkLoginPage(embedded: true, onDone: onDone, key: key);
}
