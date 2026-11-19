// The rows that say where replies come from — 渠道, 模型, 思考 — shared by
// 酒馆设置 and the stage panel's 本局. DeepSeek's own channel offers its two
// models as pills and 「自定义」 for any other name; an added channel's model
// is edited on that channel.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/quwork_auth_state.dart';
import '../../state/quwork_models_state.dart';
import '../../tavern/tavern_settings.dart';
import '../auth/quwork_login_page.dart';
import '../settings/settings_widgets.dart';
import '../theme/app_icons.dart';

/// [keyPrefix] tells the two places apart (`tavern` / `tavern-session`);
/// [tinted] false draws the icons as on secondary pages; [open] pushes a
/// page (the stage panel closes its drawer first).
List<Widget> tavernModelRows(
  BuildContext context,
  WidgetRef ref, {
  required String keyPrefix,
  bool tinted = true,
  bool thinkingSubtitle = true,
  void Function(Route<void> route)? open,
}) {
  final l10n = context.l10n;
  final settings = ref.watch(tavernSettingsProvider);
  final controller = ref.read(tavernSettingsProvider.notifier);
  final auth = ref.watch(quWorkAuthProvider);
  final models = ref.watch(quWorkModelsProvider).models;
  final push = open ?? (route) => unawaited(Navigator.of(context).push(route));
  final modelIds = [for (final model in models) model.id];
  final selectedModel = modelIds.contains(settings.model) ? settings.model : modelIds.firstOrNull;

  return [
    SettingsTile(
      key: ValueKey('$keyPrefix-quwork'),
      icon: AppIcons.providers,
      tinted: tinted,
      title: l10n.quworkLoginTitle,
      value: Text(auth.signedIn ? l10n.quworkLoginSignedIn : l10n.quworkLoginSignInHint),
      onTap: () => push(MaterialPageRoute<void>(builder: (_) => const QuWorkLoginPage())),
    ),
    if (models.isEmpty)
      SettingsTile(
        key: ValueKey('$keyPrefix-model'),
        icon: AppIcons.model,
        tinted: tinted,
        title: l10n.tavernSettingsModel,
        value: Text(l10n.quworkLoginSignInHint),
      )
    else
      SettingsSegmentTile<String>(
        key: ValueKey('$keyPrefix-model'),
        icon: AppIcons.model,
        tinted: tinted,
        title: l10n.tavernSettingsModel,
        segments: [for (final model in models) PillSegment(model.id, model.name ?? model.id)],
        selected: selectedModel ?? modelIds.first,
        onChanged: (model) => unawaited(controller.setModel(model)),
      ),
    SettingsSwitchTile(
      key: ValueKey('$keyPrefix-thinking'),
      icon: AppIcons.generating,
      tinted: tinted,
      title: l10n.tavernThinking,
      subtitle: thinkingSubtitle ? l10n.tavernThinkingSubtitle : null,
      value: settings.thinking,
      onChanged: (on) => unawaited(controller.setThinking(on)),
    ),
  ];
}
