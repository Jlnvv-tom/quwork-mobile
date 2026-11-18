import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quwork_api/quwork_api.dart';

import 'models_state.dart';
import 'providers_state.dart';
import 'quwork_auth_state.dart';

enum QuWorkModelsPhase { idle, loading, ready, failed }

class QuWorkModelsState {
  const QuWorkModelsState({this.phase = QuWorkModelsPhase.idle, this.models = const [], this.error, this.loadedAt});
  final QuWorkModelsPhase phase;
  final List<QuWorkModel> models;
  final Object? error;
  final DateTime? loadedAt;
}

class QuWorkModelsController extends Notifier<QuWorkModelsState> {
  @override
  QuWorkModelsState build() {
    final auth = ref.watch(quWorkAuthProvider);
    if (auth.signedIn) unawaited(refresh());
    return const QuWorkModelsState();
  }

  Future<void> refresh() async {
    if (state.phase == QuWorkModelsPhase.loading) return;
    state = QuWorkModelsState(phase: QuWorkModelsPhase.loading, models: state.models);
    try {
      final models = await ref.read(quWorkAuthProvider.notifier).availableModels();
      if (ref.mounted)
        state = QuWorkModelsState(phase: QuWorkModelsPhase.ready, models: models, loadedAt: DateTime.now());
    } catch (error) {
      if (ref.mounted) state = QuWorkModelsState(phase: QuWorkModelsPhase.failed, models: state.models, error: error);
    }
  }
}

final quWorkModelsProvider = NotifierProvider<QuWorkModelsController, QuWorkModelsState>(QuWorkModelsController.new);

/// Mirrors the account model entitlement into the active DSH Host's provider
/// catalog. The key is written through the Host credential API; it never enters
/// the Flutter model state or ordinary preferences.
final quWorkProviderSyncProvider = FutureProvider.autoDispose<void>((ref) async {
  final auth = ref.watch(quWorkAuthProvider);
  final models = ref.watch(quWorkModelsProvider);
  final backend = ref.watch(providerBackendProvider);
  if (!auth.signedIn || models.models.isEmpty || backend == null) return;
  final llmToken = await ref.read(quWorkAuthProvider.notifier).modelToken();
  if (llmToken == null) return;
  const route = 'quwork';
  final existing = (await backend.read())?.byRoute(route);
  final specs = [
    for (final model in models.models)
      ProviderModelSpec(id: model.id, name: model.name, contextWindow: model.contextWindow, maxTokens: model.maxTokens),
  ];
  final baseUrl = const String.fromEnvironment('QUWORK_LLM_BASE_URL', defaultValue: 'https://llm.rrzu.com/v1');
  if (existing == null) {
    await backend.create(
      ProviderProfile(
        route: route,
        displayName: 'QuWork',
        api: ProviderApi.openaiCompletions.wire,
        baseUrl: baseUrl,
        apiKeyEnv: 'QUWORK_LLM_TOKEN',
        models: specs,
      ),
    );
  } else {
    await backend.update(
      route,
      displayName: 'QuWork',
      api: ProviderApi.openaiCompletions,
      baseUrl: baseUrl,
      apiKeyEnv: 'QUWORK_LLM_TOKEN',
      models: specs,
    );
  }
  await backend.storeKey('QUWORK_LLM_TOKEN', llmToken);
  ref.invalidate(modelCatalogProvider);
});

/// A model group for screens that need to show account entitlements before a
/// Host is connected. Chat routing still requires [quWorkProviderSyncProvider].
final quWorkModelGroupProvider = Provider<ProviderGroup?>((ref) {
  final state = ref.watch(quWorkModelsProvider);
  if (state.models.isEmpty) return null;
  return ProviderGroup('quwork', 'QuWork', [
    for (final model in state.models)
      ModelInfo(provider: 'quwork', id: model.id, name: model.name ?? model.id, description: 'QuWork account model'),
  ]);
});

final quWorkMergedCatalogProvider = Provider<ModelCatalog?>((ref) {
  final catalog = ref.watch(modelListViewProvider).value;
  final group = ref.watch(quWorkModelGroupProvider);
  if (catalog == null || group == null) return catalog;
  if (catalog.groups.any((entry) => entry.id == group.id)) return catalog;
  return ModelCatalog(
    defaultSelection: catalog.defaultSelection,
    routableProviders: [...catalog.routableProviders, group.id],
    groups: [...catalog.groups, group],
    failures: catalog.failures,
  );
});
