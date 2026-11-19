import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/quwork_auth_state.dart';
import '../../state/quwork_models_state.dart';
import '../auth/quwork_login_page.dart';
import '../common/list_page_row.dart';
import '../common/status_chip.dart';
import '../shell/page_frame.dart';
import 'new_chat_defaults_card.dart';
import 'provider_widgets.dart';

class ProvidersPage extends ConsumerWidget {
  const ProvidersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      AppPage.list(title: context.l10n.engineProvidersTitle, children: const [NewChatDefaultsCard(), _QuWorkCard()]);
}

class _QuWorkCard extends ConsumerWidget {
  const _QuWorkCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final auth = ref.watch(quWorkAuthProvider);
    final models = ref.watch(quWorkModelsProvider);
    final signedIn = auth.signedIn;
    final subtitle = !signedIn
        ? l10n.quworkLoginSignInHint
        : models.phase == QuWorkModelsPhase.loading
        ? l10n.quworkLoginWorking
        : models.models.isEmpty
        ? l10n.quworkLoginFailed
        : '${models.models.length} · ${l10n.quworkUsageSummary}';
    return ListPageCard(
      title: l10n.quworkLoginTitle,
      children: [
        ListPageRow(
          leading: const Monogram('QuWork'),
          title: 'QuWork',
          subtitle: subtitle,
          trailing: ProviderDot(signedIn && models.models.isNotEmpty ? StatusTone.ok : StatusTone.idle),
          chevron: true,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const QuWorkLoginPage())),
        ),
        if (signedIn)
          for (final model in models.models)
            ListPageRow(
              leading: Monogram(model.name ?? model.id),
              title: model.name ?? model.id,
              subtitle: l10n.quworkUsageSummary,
              trailing: const ProviderDot(StatusTone.ok),
            ),
      ],
    );
  }
}

class LoginCapsule extends StatelessWidget {
  const LoginCapsule({super.key, required this.onPressed, this.semanticLabel});

  static const height = 32.0;

  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    button: true,
    excludeSemantics: semanticLabel != null,
    child: FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, height),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const StadiumBorder(),
      ),
      child: Text(context.l10n.commonSignIn),
    ),
  );
}

/// For callers outside this page (the model sheet, onboarding).
void openProviders(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProvidersPage()));
