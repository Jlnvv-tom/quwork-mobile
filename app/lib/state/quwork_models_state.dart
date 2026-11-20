import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quwork_api/quwork_api.dart';

import 'model_defaults_state.dart';
import 'models_state.dart';
import 'providers_state.dart';
import 'read_list_identity.dart';
import 'quwork_auth_state.dart';

enum QuWorkModelsPhase { idle, loading, ready, failed }

class QuWorkModelsState {
  const QuWorkModelsState({this.phase = QuWorkModelsPhase.idle, this.models = const [], this.error, this.loadedAt});
  final QuWorkModelsPhase phase;
  final List<QuWorkModel> models;
  final Object? error;
  final DateTime? loadedAt;
}

ModelSelection? quWorkDefaultSelection(QuWorkModelsState state) {
  if (state.models.isEmpty) return null;
  final model = state.models.first;
  return ModelSelection(provider: 'quwork', model: model.id);
}

class QuWorkModelsController extends Notifier<QuWorkModelsState> {
  Future<void>? _refreshing;

  @override
  QuWorkModelsState build() {
    final auth = ref.watch(quWorkAuthProvider);
    if (auth.signedIn) unawaited(refresh());
    return const QuWorkModelsState();
  }

  Future<void> refresh() {
    final refreshing = _refreshing;
    if (refreshing != null) return refreshing;
    final future = _refreshNow();
    _refreshing = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_refreshing, future)) _refreshing = null;
      }),
    );
    return future;
  }

  Future<void> _refreshNow() async {
    state = QuWorkModelsState(phase: QuWorkModelsPhase.loading, models: state.models);
    try {
      final models = await ref.read(quWorkAuthProvider.notifier).availableModels();
      if (ref.mounted) {
        state = QuWorkModelsState(phase: QuWorkModelsPhase.ready, models: models, loadedAt: DateTime.now());
      }
    } catch (error) {
      if (ref.mounted) state = QuWorkModelsState(phase: QuWorkModelsPhase.failed, models: state.models, error: error);
    }
  }

  Future<bool> ensureAccess() async {
    final auth = ref.read(quWorkAuthProvider);
    if (!auth.signedIn || !auth.hasModelCredential) return false;
    if (state.models.isEmpty) await refresh();
    return ref.mounted && ref.read(quWorkModelsProvider).models.isNotEmpty;
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
  final connection = ref.watch(readListLiveConnectionProvider);
  if (!auth.signedIn) {
    if (backend != null) {
      final existing = (await backend.read())?.byRoute('quwork');
      if (existing != null && existing.apiKeyEnv == 'QUWORK_LLM_TOKEN') {
        await backend.remove('quwork', expectedRevision: (await backend.read())?.revision);
      } else {
        await backend.clearKey('QUWORK_LLM_TOKEN');
      }
      if (connection != null) ref.invalidate(modelCatalogProvider);
    }
    return;
  }
  if (models.models.isEmpty || backend == null || connection == null) return;
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

  // QuWork is the product's only model source. Replace any upstream default so
  // every request after login is charged to the QuWork account.
  try {
    final catalog = await connection.client.listModels();
    final current = catalog.defaultSelection;
    final quWorkDefault =
        models.models.isNotEmpty && current?.provider == route && current?.model == models.models.first.id;
    if (!quWorkDefault && models.models.isNotEmpty) {
      await connection.client.mutateSettings(
        defaultModelSettingsNs,
        defaultModelOps(ModelSelection(provider: route, model: models.models.first.id)),
      );
    }
  } on Object {
    // The provider and credential are already usable; a default write can be
    // retried by the next catalog refresh without blocking model access.
  }
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
  final auth = ref.watch(quWorkAuthProvider);
  if (catalog == null) return null;
  if (!auth.signedIn || group == null) {
    return const ModelCatalog(defaultSelection: null, routableProviders: [], groups: [], failures: []);
  }
  final defaultSelection =
      catalog.defaultSelection?.provider == group.id &&
          group.models.any((model) => model.id == catalog.defaultSelection?.model)
      ? catalog.defaultSelection
      : ModelSelection(provider: group.id, model: group.models.first.id);
  return ModelCatalog(
    defaultSelection: defaultSelection,
    routableProviders: [group.id],
    groups: [group],
    failures: [
      for (final failure in catalog.failures)
        if (failure.provider == group.id) failure,
    ],
  );
});
