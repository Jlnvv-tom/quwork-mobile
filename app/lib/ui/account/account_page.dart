import 'package:flutter/material.dart';

import '../auth/quwork_login_page.dart';

/// Compatibility route for upstream deep links and settings metadata.
///
/// QuWork is the only product account system. Keeping this route as a small
/// alias prevents an old `AccountPage` link from reopening the upstream
/// DeepSeek account or API-key flow.
class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) => const QuWorkLoginPage();
}
