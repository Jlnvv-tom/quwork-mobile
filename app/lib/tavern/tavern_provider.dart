// The app's one [Tavern]: the engine (packages/dsh_tavern) opened on
// `<app support>/tavern`. It opens asynchronously, so the screens get a
// [DeferredTavern] that queues calls until it is ready. Every model request
// uses the logged-in QuWork bearer token and the QuWork OpenAI-compatible
// endpoint; the engine never stores the token. Tests swap in the preview
// stand-in (tavern_preview.dart).

import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../state/quwork_auth_state.dart';
import '../state/quwork_models_state.dart';
import 'deferred_tavern.dart';
import 'tavern_channels.dart';
import 'tavern_script_host.dart';
import 'tavern_settings.dart';

final tavernProvider = Provider<Tavern>((ref) {
  final tavern = DeferredTavern(() async {
    final support = await getApplicationSupportDirectory();
    return openTavern('${support.path}/tavern');
  }());
  ref.onDispose(tavern.close);
  void configure(TavernSettings settings) {
    final models = ref.read(quWorkModelsProvider).models;
    final model = models.firstOrNull?.id ?? settings.activeModel;
    tavern.configure(
      quWorkTavernModelConfig(
        settings: settings,
        model: model,
        token: () => ref.read(quWorkAuthProvider.notifier).modelToken(),
      ),
    );
  }

  configure(ref.read(tavernSettingsProvider));
  ref.listen(tavernSettingsProvider, (_, next) => configure(next));
  ref.listen(quWorkAuthProvider, (_, _) => configure(ref.read(tavernSettingsProvider)));
  ref.listen(quWorkModelsProvider, (_, _) => configure(ref.read(tavernSettingsProvider)));
  return tavern;
});

/// The roleplay surface uses the same QuWork bearer credential as ordinary
/// chat. Saved third-party tavern channels are intentionally ignored for
/// requests so they cannot bypass QuWork usage accounting.
TavernModelConfig quWorkTavernModelConfig({
  required TavernSettings settings,
  required String model,
  required Future<String?> Function() token,
}) => TavernModelConfig(
  apiKey: token,
  baseUrl: const String.fromEnvironment('QUWORK_LLM_BASE_URL', defaultValue: 'https://llm.rrzu.com/v1'),
  model: model,
  deepseek: false,
  thinking: settings.thinking,
);

/// Compatibility helper for upstream callers and package tests. The product
/// provider above never calls this legacy upstream configuration path.
TavernModelConfig tavernModelConfig(
  TavernSettings settings, {
  required String Function() appKey,
  required TavernChannelKeys keys,
}) {
  TavernModelConfig config(
    TavernChannel? channel,
    String model, {
    bool thinking = false,
    TavernModelConfig? auxiliary,
  }) => TavernModelConfig(
    apiKey: () async {
      final key = (channel == null ? appKey() : await keys.read(channel.id))?.trim();
      return key == null || key.isEmpty ? null : key;
    },
    baseUrl: channel?.baseUrl ?? tavernDeepSeekBaseUrl,
    model: model,
    deepseek: channel?.deepseek ?? true,
    thinking: thinking,
    headers: channel?.headers ?? const {},
    auxiliary: auxiliary,
  );
  final helper = settings.auxiliaryChannel;
  return config(
    settings.activeChannel,
    settings.activeModel,
    thinking: settings.thinking,
    auxiliary: switch (settings.auxiliary) {
      tavernAuxiliaryDeepSeek => config(null, tavernModels.first),
      _ when helper != null => config(helper, helper.model),
      _ => null,
    },
  );
}

/// The app's host for card scripts, one per tavern: what the engine delivers
/// to a canvas page's script context goes to that page.
final tavernScriptPagesProvider = Provider<TavernScriptPages>((ref) {
  ref.watch(tavernProvider);
  return TavernScriptPages();
});

/// Every character, as the library lists them.
final tavernCharactersProvider = StreamProvider<List<TavernCharacter>>(
  (ref) => ref.watch(tavernProvider).watchCharacters(),
);

/// One character in full. The list carries only what a card in the grid
/// shows; greetings, the definition and the creator's notes come from here,
/// read again whenever the list changes (an edit, a re-import).
final tavernCharacterDetailProvider = FutureProvider.autoDispose.family<TavernCharacter?, String>((ref, id) {
  ref.watch(tavernCharactersProvider);
  return ref.watch(tavernProvider).character(id);
});

/// Chats, newest first; one character's when the argument is its id.
final tavernChatsProvider = StreamProvider.family<List<TavernChatSummary>, String?>(
  (ref, characterId) => ref.watch(tavernProvider).watchChats(characterId: characterId),
);

/// Saved personas (人设).
final tavernPersonasProvider = StreamProvider<List<TavernPersona>>((ref) => ref.watch(tavernProvider).watchPersonas());

/// Who you are in a chat (null: outside any chat, just the default). Read
/// again whenever the personas notify, which default and binding changes do.
final tavernPersonaSelectionProvider = FutureProvider.family<PersonaSelection, String?>((ref, chatId) {
  ref.watch(tavernPersonasProvider);
  return ref.watch(tavernProvider).personaSelection(chatId: chatId);
});

/// No model reply can be asked for until the QuWork account and its entitled
/// models are ready. There is no DeepSeek API-key path in the product.
final tavernNeedsQuWorkProvider = Provider<bool>((ref) {
  final auth = ref.watch(quWorkAuthProvider);
  final models = ref.watch(quWorkModelsProvider);
  return !auth.signedIn || !auth.hasModelCredential || models.models.isEmpty;
});

/// Source compatibility for older callers. It has QuWork-only semantics.
final tavernNeedsKeyProvider = tavernNeedsQuWorkProvider;
