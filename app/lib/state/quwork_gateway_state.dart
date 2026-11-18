import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quwork_api/quwork_api.dart';

import '../remote/secret_store.dart';
import 'hosts_state.dart';

enum QuWorkGatewayPhase { signedOut, restoring, pairing, connected, renewing, failed }

class QuWorkGatewayState {
  const QuWorkGatewayState({required this.phase, this.credential, this.error});
  final QuWorkGatewayPhase phase;
  final QuWorkGatewayCredential? credential;
  final Object? error;
  bool get connected => phase == QuWorkGatewayPhase.connected && credential != null;
}

final quWorkGatewayApiProvider = Provider<QuWorkGatewayApi>((ref) {
  final api = QuWorkGatewayApi();
  ref.onDispose(api.close);
  return api;
});

class QuWorkGatewayStore {
  const QuWorkGatewayStore(this._secrets);
  final SecretStore _secrets;
  static const key = 'quwork_gateway_credential';
  Future<QuWorkGatewayCredential?> read() async {
    final raw = await _secrets.read(key);
    if (raw == null) return null;
    try {
      return QuWorkGatewayCredential.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> write(QuWorkGatewayCredential credential) => _secrets.write(key, jsonEncode(credential.toJson()));
  Future<void> delete() => _secrets.delete(key);
}

final quWorkGatewayStoreProvider = Provider<QuWorkGatewayStore>(
  (ref) => QuWorkGatewayStore(ref.read(secretStoreProvider)),
);

class QuWorkGatewayController extends Notifier<QuWorkGatewayState> {
  @override
  QuWorkGatewayState build() {
    unawaited(_restore());
    return const QuWorkGatewayState(phase: QuWorkGatewayPhase.restoring);
  }

  QuWorkGatewayApi get _api => ref.read(quWorkGatewayApiProvider);
  QuWorkGatewayStore get _store => ref.read(quWorkGatewayStoreProvider);

  Future<void> _restore() async {
    final credential = await _store.read();
    if (!ref.mounted) return;
    if (credential == null) {
      state = const QuWorkGatewayState(phase: QuWorkGatewayPhase.signedOut);
      return;
    }
    try {
      if (await _api.probe(credential)) {
        state = QuWorkGatewayState(phase: QuWorkGatewayPhase.connected, credential: credential);
      } else {
        state = const QuWorkGatewayState(phase: QuWorkGatewayPhase.signedOut);
      }
    } catch (error) {
      state = QuWorkGatewayState(phase: QuWorkGatewayPhase.failed, credential: credential, error: error);
    }
  }

  Future<bool> pair(Uri qr, {String? label}) async {
    state = const QuWorkGatewayState(phase: QuWorkGatewayPhase.pairing);
    try {
      final pairing = QuWorkGatewayPairing.fromQr(qr);
      final credential = await _api.pair(pairing, label: label ?? 'QuWork 手机');
      await _store.write(credential);
      if (ref.mounted) state = QuWorkGatewayState(phase: QuWorkGatewayPhase.connected, credential: credential);
      return true;
    } catch (error) {
      if (ref.mounted) state = QuWorkGatewayState(phase: QuWorkGatewayPhase.failed, error: error);
      return false;
    }
  }

  Future<bool> renew() async {
    final credential = state.credential ?? await _store.read();
    if (credential == null) return false;
    state = QuWorkGatewayState(phase: QuWorkGatewayPhase.renewing, credential: credential);
    try {
      final renewed = await _api.renew(credential);
      await _store.write(renewed);
      if (ref.mounted) state = QuWorkGatewayState(phase: QuWorkGatewayPhase.connected, credential: renewed);
      return true;
    } catch (error) {
      if (ref.mounted)
        state = QuWorkGatewayState(phase: QuWorkGatewayPhase.failed, credential: credential, error: error);
      return false;
    }
  }

  Future<void> signOut() async {
    final credential = state.credential;
    if (credential != null) {
      try {
        await _api.logout(credential);
      } catch (_) {}
    }
    await _store.delete();
    if (ref.mounted) state = const QuWorkGatewayState(phase: QuWorkGatewayPhase.signedOut);
  }
}

final quWorkGatewayProvider = NotifierProvider<QuWorkGatewayController, QuWorkGatewayState>(
  QuWorkGatewayController.new,
);
