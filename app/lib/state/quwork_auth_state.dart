import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quwork_api/quwork_api.dart';

import '../secrets/secure_storage.dart';

enum QuWorkAuthPhase {
  unknown,
  signedOut,
  restoring,
  sendingCode,
  captchaRequired,
  signingIn,
  wechatBindingRequired,
  refreshing,
  signedIn,
  failed,
}

class QuWorkAuthState {
  const QuWorkAuthState({
    required this.phase,
    this.user,
    this.accessTokenExpiresAt,
    this.hasModelCredential = false,
    this.wechatBindingToken,
    this.error,
  });

  const QuWorkAuthState.unknown() : this(phase: QuWorkAuthPhase.unknown);

  final QuWorkAuthPhase phase;
  final QuWorkUser? user;
  final DateTime? accessTokenExpiresAt;
  final bool hasModelCredential;
  final String? wechatBindingToken;
  final QuWorkApiException? error;

  bool get signedIn => phase == QuWorkAuthPhase.signedIn && user != null;
  bool get busy =>
      phase == QuWorkAuthPhase.restoring ||
      phase == QuWorkAuthPhase.sendingCode ||
      phase == QuWorkAuthPhase.captchaRequired ||
      phase == QuWorkAuthPhase.signingIn ||
      phase == QuWorkAuthPhase.refreshing;
}

abstract interface class QuWorkAuthStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureQuWorkAuthStore implements QuWorkAuthStore {
  const SecureQuWorkAuthStore();
  static const _prefix = 'quwork.';
  final _storage = const AppSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: '$_prefix$key');

  @override
  Future<void> write(String key, String value) => _storage.write(key: '$_prefix$key', value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: '$_prefix$key');
}

final quWorkAuthStoreProvider = Provider<QuWorkAuthStore>((ref) => const SecureQuWorkAuthStore());

final quWorkApiProvider = Provider<QuWorkAuthApi>((ref) {
  final api = QuWorkAuthApi(
    baseUri: Uri.parse(const String.fromEnvironment('QUWORK_API_BASE_URL', defaultValue: 'https://llm.rrzu.com')),
  );
  ref.onDispose(api.close);
  return api;
});

class QuWorkAuthController extends Notifier<QuWorkAuthState> {
  static const _recordKey = 'auth';
  int _generation = 0;
  Future<void> _writeQueue = Future<void>.value();

  @override
  QuWorkAuthState build() {
    unawaited(_restore(++_generation));
    return const QuWorkAuthState(phase: QuWorkAuthPhase.restoring);
  }

  QuWorkAuthStore get _store => ref.read(quWorkAuthStoreProvider);
  QuWorkAuthApi get _api => ref.read(quWorkApiProvider);
  bool _live(int generation) => ref.mounted && generation == _generation;

  Future<String?> accessToken() async {
    final raw = await _store.read(_recordKey);
    final map = raw == null ? null : jsonDecode(raw);
    final token = map is Map ? map['token'] : null;
    return token is String && token.isNotEmpty ? token : null;
  }

  Future<String?> modelToken() async {
    final raw = await _store.read(_recordKey);
    final map = raw == null ? null : jsonDecode(raw);
    final token = map is Map ? map['llmToken'] : null;
    return token is String && token.isNotEmpty ? token : null;
  }

  Future<void> _inOrder(Future<void> Function() operation) {
    final done = _writeQueue.then((_) => operation());
    _writeQueue = done.catchError((_) {});
    return done;
  }

  Future<void> _restore(int generation) async {
    try {
      final raw = await _store.read(_recordKey);
      final map = raw == null ? null : jsonDecode(raw);
      final token = map is Map ? map['token'] : null;
      final expiry = map is Map ? map['expiresAt'] : null;
      final llmToken = map is Map && map['llmToken'] is String ? map['llmToken'] as String : null;
      final expires = expiry is String ? DateTime.tryParse(expiry) : null;
      if (token is String && token.isNotEmpty && expires != null) {
        final user = await _api.self(token);
        if (_live(generation)) {
          state = QuWorkAuthState(
            phase: QuWorkAuthPhase.signedIn,
            user: user,
            accessTokenExpiresAt: expires,
            hasModelCredential: llmToken?.isNotEmpty == true,
          );
          return;
        }
      }
    } on Object {
      // An unreadable or expired record is signed out; the next login replaces it.
    }
    if (_live(generation)) state = const QuWorkAuthState(phase: QuWorkAuthPhase.signedOut);
  }

  Future<QuWorkSendCodeResult?> sendCode(
    String phone, {
    String? captcha,
    QuWorkCaptchaProvider? captchaProvider,
  }) async {
    final generation = ++_generation;
    if (!_live(generation)) return null;
    state = const QuWorkAuthState(phase: QuWorkAuthPhase.sendingCode);
    try {
      final resolvedCaptcha =
          captcha ?? await (captchaProvider ?? const DisabledQuWorkCaptchaProvider()).solve(phone: phone);
      final result = await _api.sendLoginCode(phone, aliyunCaptcha: resolvedCaptcha);
      if (_live(generation)) state = const QuWorkAuthState(phase: QuWorkAuthPhase.signedOut);
      return result;
    } on QuWorkApiException catch (error) {
      if (_live(generation)) state = QuWorkAuthState(phase: QuWorkAuthPhase.failed, error: error);
      return null;
    }
  }

  Future<bool> login(String phone, String code, {String? wechatToken}) async {
    final generation = ++_generation;
    state = const QuWorkAuthState(phase: QuWorkAuthPhase.signingIn);
    try {
      final result = await _api.loginByPhone(phone, code, wechatToken: wechatToken);
      await _inOrder(
        () => _store.write(
          _recordKey,
          jsonEncode({
            'token': result.token,
            'expiresAt': result.expiresAt.toIso8601String(),
            'llmToken': ?result.llmToken,
          }),
        ),
      );
      if (!_live(generation)) return false;
      state = QuWorkAuthState(
        phase: QuWorkAuthPhase.signedIn,
        user: result.user,
        accessTokenExpiresAt: result.expiresAt,
        hasModelCredential: result.llmToken?.isNotEmpty == true,
      );
      return true;
    } on QuWorkApiException catch (error) {
      if (_live(generation)) state = QuWorkAuthState(phase: QuWorkAuthPhase.failed, error: error);
      return false;
    }
  }

  Future<QuWorkWechatLoginStart?> startWechatLogin() async {
    try {
      return await _api.startWechatLogin();
    } on QuWorkApiException catch (error) {
      if (ref.mounted) state = QuWorkAuthState(phase: QuWorkAuthPhase.failed, error: error);
      return null;
    }
  }

  Future<bool> finishWechatCallback(Uri callback) async {
    final generation = ++_generation;
    try {
      final result = await _api.finishWechatLogin(callback);
      final login = result.login;
      if (login != null) return await _saveLogin(login, generation);
      if (result.requiresBinding && _live(generation)) {
        state = QuWorkAuthState(phase: QuWorkAuthPhase.wechatBindingRequired, wechatBindingToken: result.wechatToken);
        return false;
      }
      throw const QuWorkApiException('wechat_bind_required', '微信账号需要绑定手机号');
    } on QuWorkApiException catch (error) {
      if (_live(generation)) state = QuWorkAuthState(phase: QuWorkAuthPhase.failed, error: error);
      return false;
    }
  }

  Future<bool> bindWechat() async {
    final wechatToken = state.wechatBindingToken;
    final token = await accessToken();
    if (wechatToken == null || token == null) return false;
    try {
      await _api.bindWechat(token, wechatToken);
      if (ref.mounted)
        state = QuWorkAuthState(
          phase: QuWorkAuthPhase.signedIn,
          user: state.user,
          accessTokenExpiresAt: state.accessTokenExpiresAt,
          hasModelCredential: state.hasModelCredential,
        );
      return true;
    } on QuWorkApiException catch (error) {
      if (ref.mounted) state = QuWorkAuthState(phase: QuWorkAuthPhase.failed, error: error);
      return false;
    }
  }

  Future<bool> _saveLogin(QuWorkLoginResult result, int generation) async {
    await _inOrder(
      () => _store.write(
        _recordKey,
        jsonEncode({
          'token': result.token,
          'expiresAt': result.expiresAt.toIso8601String(),
          'llmToken': ?result.llmToken,
        }),
      ),
    );
    if (!_live(generation)) return false;
    state = QuWorkAuthState(
      phase: QuWorkAuthPhase.signedIn,
      user: result.user,
      accessTokenExpiresAt: result.expiresAt,
      hasModelCredential: result.llmToken?.isNotEmpty == true,
    );
    return true;
  }

  Future<List<QuWorkModel>> availableModels() async {
    final token = await accessToken();
    if (token == null) throw const QuWorkApiException('token_expired', '登录已过期');
    return _api.availableModelDetails(token);
  }

  Future<bool> refresh() async {
    final generation = ++_generation;
    try {
      final raw = await _store.read(_recordKey);
      final map = raw == null ? null : jsonDecode(raw);
      final token = map is Map && map['token'] is String ? map['token'] as String : null;
      final llmToken = map is Map && map['llmToken'] is String ? map['llmToken'] as String : null;
      if (token == null) throw const QuWorkApiException('token_expired', '登录已过期');
      final result = await _api.refresh(token);
      final nextLlmToken = result.llmToken ?? llmToken;
      await _inOrder(
        () => _store.write(
          _recordKey,
          jsonEncode({
            'token': result.token,
            'expiresAt': result.expiresAt.toIso8601String(),
            'llmToken': ?nextLlmToken,
          }),
        ),
      );
      if (!_live(generation)) return false;
      state = QuWorkAuthState(
        phase: QuWorkAuthPhase.signedIn,
        user: result.user,
        accessTokenExpiresAt: result.expiresAt,
        hasModelCredential: nextLlmToken?.isNotEmpty == true,
      );
      return true;
    } on QuWorkApiException catch (error) {
      if (_live(generation)) state = QuWorkAuthState(phase: QuWorkAuthPhase.failed, error: error);
      return false;
    }
  }

  Future<void> signOut() async {
    ++_generation;
    try {
      final raw = await _store.read(_recordKey);
      final map = raw == null ? null : jsonDecode(raw);
      final token = map is Map && map['token'] is String ? map['token'] as String : null;
      if (token != null) await _api.logout(token);
    } on Object {
      // Local removal is still attempted; the server may be unreachable.
    }
    await _inOrder(() => _store.delete(_recordKey));
    if (ref.mounted) state = const QuWorkAuthState(phase: QuWorkAuthPhase.signedOut);
  }
}

final quWorkAuthProvider = NotifierProvider<QuWorkAuthController, QuWorkAuthState>(QuWorkAuthController.new);
