library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class QuWorkApiException implements Exception {
  const QuWorkApiException(this.code, this.message, {this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'QuWorkApiException($code)';
}

class QuWorkUser {
  const QuWorkUser({
    this.id,
    this.username,
    this.phone,
    this.displayName,
    this.status,
    this.activated,
    this.wechatBound,
  });

  final int? id;
  final String? username;
  final String? phone;
  final String? displayName;
  final int? status;
  final bool? activated;
  final bool? wechatBound;

  String get label {
    for (final value in [displayName, phone, username]) {
      if (value case final text? when text.trim().isNotEmpty) {
        return text.trim();
      }
    }
    return 'QuWork';
  }

  Map<String, Object?> toJson() => {
    'id': ?id,
    'username': ?username,
    'phone': ?phone,
    'displayName': ?displayName,
    'status': ?status,
    'activated': ?activated,
    'wechatBound': ?wechatBound,
  };

  factory QuWorkUser.fromJson(Object? value) {
    final map = _asMap(value);
    if (map == null) throw const QuWorkApiException('invalid_user', '用户资料格式无效');
    bool? boolValue(Object? value) => switch (value) {
      bool v => v,
      num v => v != 0,
      String v when v == '1' || v.toLowerCase() == 'true' => true,
      String v when v == '0' || v.toLowerCase() == 'false' => false,
      _ => null,
    };
    int? intValue(Object? value) =>
        value is num ? value.toInt() : int.tryParse('$value');
    String? text(String key) => switch (map[key]) {
      String v when v.trim().isNotEmpty => v,
      _ => null,
    };
    return QuWorkUser(
      id: intValue(map['id']),
      username: text('username'),
      phone: text('phone'),
      displayName: text('display_name') ?? text('displayName'),
      status: intValue(map['status']),
      activated: boolValue(map['activated']),
      wechatBound: boolValue(map['wechat_bound'] ?? map['wechatBound']),
    );
  }
}

class QuWorkLoginResult {
  const QuWorkLoginResult({
    required this.token,
    required this.expiresAt,
    required this.user,
    this.llmToken,
  });

  final String token;
  final DateTime expiresAt;
  final QuWorkUser user;
  final String? llmToken;
}

class QuWorkSendCodeResult {
  const QuWorkSendCodeResult({required this.message});
  final String message;
}

/// Captcha is intentionally a seam: the production app can use the provider
/// configured by the account service, while simulator tests can inject a
/// deterministic short-lived ticket without embedding an SDK.
abstract interface class QuWorkCaptchaProvider {
  Future<String?> solve({required String phone});
}

class DisabledQuWorkCaptchaProvider implements QuWorkCaptchaProvider {
  const DisabledQuWorkCaptchaProvider();
  @override
  Future<String?> solve({required String phone}) async => null;
}

class FixedQuWorkCaptchaProvider implements QuWorkCaptchaProvider {
  const FixedQuWorkCaptchaProvider(this.token);
  final String? token;
  @override
  Future<String?> solve({required String phone}) async => token;
}

class QuWorkWechatLoginStart {
  const QuWorkWechatLoginStart({required this.url, this.state});
  final Uri url;
  final String? state;
}

class QuWorkWechatLoginResult {
  const QuWorkWechatLoginResult({this.login, this.wechatToken, this.bindType});
  final QuWorkLoginResult? login;
  final String? wechatToken;
  final String? bindType;

  bool get requiresBinding => bindType == 'need_bind' && wechatToken != null;
}

class QuWorkModel {
  const QuWorkModel({
    required this.id,
    this.name,
    this.provider,
    this.contextWindow,
    this.maxTokens,
  });
  final String id;
  final String? name;
  final String? provider;
  final int? contextWindow;
  final int? maxTokens;

  factory QuWorkModel.fromJson(Object? value) {
    final map = _asMap(value);
    if (map == null)
      throw const QuWorkApiException('invalid_response', '模型格式无效');
    int? integer(Object? value) =>
        value is num ? value.toInt() : int.tryParse('$value');
    String? text(String key) => _optionalText(map[key]);
    final id = text('id') ?? text('model');
    if (id == null)
      throw const QuWorkApiException('invalid_response', '模型 ID 缺失');
    return QuWorkModel(
      id: id,
      name: text('name') ?? text('display_name'),
      provider: text('provider'),
      contextWindow: integer(map['context_window'] ?? map['contextWindow']),
      maxTokens: integer(map['max_tokens'] ?? map['maxTokens']),
    );
  }
}

class QuWorkGatewayMetadata {
  const QuWorkGatewayMetadata({
    required this.origin,
    required this.instanceId,
    this.deviceName,
    this.expiresAt,
  });
  final Uri origin;
  final String instanceId;
  final String? deviceName;
  final DateTime? expiresAt;
}

class QuWorkGatewayPairing {
  const QuWorkGatewayPairing({
    required this.origin,
    required this.token,
    this.instanceId,
    this.caFingerprint,
  });
  final Uri origin;
  final String token;
  final String? instanceId;
  final String? caFingerprint;

  factory QuWorkGatewayPairing.fromQr(Uri uri) {
    final fragment = uri.fragment;
    final query = Uri.splitQueryString(
      fragment.startsWith('?') ? fragment.substring(1) : fragment,
    );
    var token = query['token'];
    var instanceId =
        query['instanceId'] ?? query['instance_id'] ?? query['instance'];
    var ca = query['ca'] ?? query['caFingerprint'];
    final key = query['key'];
    if (key != null) {
      final parts = key.split('.');
      if (parts.length == 3 && parts[0] == 'dsh2') {
        instanceId = parts[1];
        token = parts[2];
        ca = 'required';
      }
    }
    if (token == null || token.isEmpty) {
      throw const QuWorkApiException('invalid_pairing_qr', '配对二维码缺少一次性凭据');
    }
    final origin = uri.replace(path: '', query: null, fragment: null);
    return QuWorkGatewayPairing(
      origin: origin,
      token: token,
      instanceId: instanceId,
      caFingerprint: ca,
    );
  }
}

class QuWorkGatewayCredential {
  const QuWorkGatewayCredential({
    required this.origin,
    required this.deviceId,
    required this.deviceToken,
    required this.sessionToken,
    required this.csrfToken,
    required this.sessionExpiresAt,
    this.deviceExpiresAt,
    this.instanceId,
    this.caFingerprint,
  });
  final Uri origin;
  final String deviceId;
  final String deviceToken;
  final String sessionToken;
  final String csrfToken;
  final DateTime sessionExpiresAt;
  final DateTime? deviceExpiresAt;
  final String? instanceId;
  final String? caFingerprint;

  Map<String, Object?> toJson() => {
    'origin': origin.toString(),
    'deviceId': deviceId,
    'deviceToken': deviceToken,
    'sessionToken': sessionToken,
    'csrfToken': csrfToken,
    'sessionExpiresAt': sessionExpiresAt.toIso8601String(),
    if (deviceExpiresAt != null)
      'deviceExpiresAt': deviceExpiresAt!.toIso8601String(),
    if (instanceId != null) 'instanceId': instanceId,
    if (caFingerprint != null) 'caFingerprint': caFingerprint,
  };

  factory QuWorkGatewayCredential.fromJson(Object? value) {
    final map = _asMap(value);
    if (map == null)
      throw const QuWorkApiException(
        'invalid_gateway_credential',
        'Gateway 凭据格式无效',
      );
    String required(String key) =>
        _requiredText(map[key], 'invalid_gateway_credential', 'Gateway 凭据缺失');
    final origin = Uri.tryParse(required('origin'));
    final sessionExpiresAt = DateTime.tryParse(required('sessionExpiresAt'));
    if (origin == null || sessionExpiresAt == null)
      throw const QuWorkApiException(
        'invalid_gateway_credential',
        'Gateway 凭据格式无效',
      );
    DateTime? date(String key) =>
        map[key] is String ? DateTime.tryParse(map[key] as String) : null;
    return QuWorkGatewayCredential(
      origin: origin,
      deviceId: required('deviceId'),
      deviceToken: required('deviceToken'),
      sessionToken: required('sessionToken'),
      csrfToken: required('csrfToken'),
      sessionExpiresAt: sessionExpiresAt,
      deviceExpiresAt: date('deviceExpiresAt'),
      instanceId: _optionalText(map['instanceId']),
      caFingerprint: _optionalText(map['caFingerprint']),
    );
  }
}

class QuWorkAuthApi {
  QuWorkAuthApi({
    required Uri baseUri,
    http.Client? client,
    this.version = '1.1.0',
    this.platform = 'qurvis',
  }) : baseUri = _origin(baseUri),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final Uri baseUri;
  final String version;
  final String platform;
  final http.Client _client;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<QuWorkSendCodeResult> sendLoginCode(
    String phone, {
    String? aliyunCaptcha,
  }) async {
    final query = <String, String>{
      if (aliyunCaptcha case final captcha? when captcha.isNotEmpty)
        'aliyun_captcha': captcha,
    };
    final response = await _request(
      'POST',
      '/api/sendVerifyCode',
      query: query,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: <String, Object?>{'phone': phone, 'type': 'login'},
    );
    return QuWorkSendCodeResult(message: _message(response));
  }

  Future<QuWorkLoginResult> loginByPhone(
    String phone,
    String code, {
    String? wechatToken,
  }) async {
    final response = await _request(
      'POST',
      '/api/user/client/login',
      headers: {'Content-Type': 'application/json'},
      body: {
        'phone': phone,
        'verification_code': code,
        'platform': platform,
        if (wechatToken case final token? when token.isNotEmpty)
          'wechat_token': token,
      },
    );
    final data = _asMap(response['data']);
    if (data == null) {
      throw const QuWorkApiException('invalid_response', '登录响应格式无效');
    }
    final token = _requiredText(data['token'], 'invalid_response', '登录凭据缺失');
    final user = QuWorkUser.fromJson(data['user']);
    final expire = _requiredEpoch(data['expire']);
    final llmToken = _optionalText(data['llm_token']);
    return QuWorkLoginResult(
      token: token,
      expiresAt: expire,
      user: user,
      llmToken: llmToken,
    );
  }

  Future<QuWorkUser> self(String token) async {
    final response = await _request('GET', '/api/user/self', token: token);
    return QuWorkUser.fromJson(response['data']);
  }

  Future<QuWorkLoginResult> refresh(String token) async {
    final response = await _request('GET', '/api/user/refresh', token: token);
    final data = _asMap(response['data']);
    if (data == null) {
      throw const QuWorkApiException('invalid_response', '刷新响应格式无效');
    }
    final nextToken = _requiredText(
      data['token'],
      'invalid_response',
      '刷新凭据缺失',
    );
    final user = await self(nextToken);
    return QuWorkLoginResult(
      token: nextToken,
      expiresAt: _requiredEpoch(data['expire']),
      user: user,
    );
  }

  Future<List<String>> availableModels(String token) async {
    final response = await _request(
      'GET',
      '/api/user/available_models',
      token: token,
    );
    final data = response['data'];
    if (data is! List) {
      throw const QuWorkApiException('invalid_response', '模型列表格式无效');
    }
    return [
      for (final value in data)
        if (value is String && value.trim().isNotEmpty) value,
    ];
  }

  Future<QuWorkWechatLoginStart> startWechatLogin() async {
    final response = await _request('GET', '/api/oauth/wechat/url');
    final data = _asMap(response['data']);
    final raw = _requiredText(data?['url'], 'invalid_response', '微信登录地址缺失');
    final url = Uri.tryParse(raw);
    if (url == null || !url.hasScheme)
      throw const QuWorkApiException('invalid_response', '微信登录地址无效');
    return QuWorkWechatLoginStart(
      url: url,
      state: _optionalText(data?['state']),
    );
  }

  Future<QuWorkWechatLoginResult> finishWechatLogin(Uri callback) async {
    final query = <String, String>{
      if (callback.queryParameters['code'] case final code?
          when code.isNotEmpty)
        'code': code,
      if (callback.queryParameters['state'] case final state?
          when state.isNotEmpty)
        'state': state,
      'platform': platform,
    };
    final response = await _request(
      'GET',
      '/api/oauth/wechat',
      query: query,
      acceptFailureData: true,
    );
    final data = _asMap(response['data']);
    if (data == null)
      throw const QuWorkApiException('invalid_response', '微信登录响应格式无效');
    final token = _optionalText(data['token']);
    if (token != null) {
      final user = QuWorkUser.fromJson(data['user']);
      return QuWorkWechatLoginResult(
        login: QuWorkLoginResult(
          token: token,
          expiresAt: _requiredEpoch(data['expire']),
          user: user,
          llmToken: _optionalText(data['llm_token']),
        ),
      );
    }
    return QuWorkWechatLoginResult(
      wechatToken: _optionalText(data['wechat_token']),
      bindType: _optionalText(data['bind_type']),
    );
  }

  Future<void> bindWechat(String token, String wechatToken) async {
    await _request(
      'POST',
      '/api/user/wechat/bind',
      token: token,
      headers: {'Content-Type': 'application/json'},
      body: {'wechat_token': wechatToken},
    );
  }

  Future<List<QuWorkModel>> availableModelDetails(String token) async {
    final response = await _request(
      'GET',
      '/api/user/available_models',
      token: token,
    );
    final data = response['data'];
    if (data is! List)
      throw const QuWorkApiException('invalid_response', '模型列表格式无效');
    return [
      for (final value in data)
        value is String ? QuWorkModel(id: value) : QuWorkModel.fromJson(value),
    ];
  }

  Future<void> logout(String token) async {
    await _request('GET', '/api/user/logout', token: token);
  }

  Future<Map<String, Object?>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Map<String, Object?>? body,
    String? token,
    bool acceptFailureData = false,
  }) async {
    final uri = baseUri.replace(
      path: '${baseUri.path.replaceFirst(RegExp(r'/$'), '')}$path',
      queryParameters: query,
    );
    final request = http.Request(method, uri);
    request.headers.addAll({
      'Accept': 'application/json',
      'X-QurWork-Version': version,
      ...?headers,
    });
    if (token case final value? when value.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $value';
    }
    if (body != null) {
      if (request.headers['Content-Type'] ==
          'application/x-www-form-urlencoded') {
        request.bodyFields = {
          for (final entry in body.entries) entry.key: '${entry.value ?? ''}',
        };
      } else {
        request.body = jsonEncode(body);
      }
    }
    http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const QuWorkApiException('timeout', '请求超时');
    } on http.ClientException catch (error) {
      throw QuWorkApiException('network_unreachable', error.message);
    }
    Map<String, Object?> payload;
    try {
      final decoded = jsonDecode(response.body);
      final map = _asMap(decoded);
      if (map == null) throw const FormatException();
      payload = map;
    } on Object {
      throw QuWorkApiException(
        'invalid_response',
        '服务响应格式无效',
        statusCode: response.statusCode,
      );
    }
    final success = _success(payload['success']);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        (success == false && !acceptFailureData)) {
      throw QuWorkApiException(
        _errorCode(response.statusCode),
        _message(payload),
        statusCode: response.statusCode,
      );
    }
    if (success != true && !(acceptFailureData && success == false)) {
      throw QuWorkApiException(
        'invalid_response',
        '服务响应格式无效',
        statusCode: response.statusCode,
      );
    }
    return payload;
  }
}

class QuWorkGatewayApi {
  QuWorkGatewayApi({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;
  final http.Client _client;
  final bool _ownsClient;
  void close() {
    if (_ownsClient) _client.close();
  }

  /// Headers for authenticated DSH Web HTTP calls after native pairing. The
  /// session token is kept in secure storage by the App state layer.
  Map<String, String> authenticatedHeaders(QuWorkGatewayCredential credential) => {
    'Cookie': 'dsh_ma_session=${credential.sessionToken}',
    'X-CSRF-Token': credential.csrfToken,
  };

  Uri websocketUri(QuWorkGatewayCredential credential, String path) {
    final scheme = credential.origin.scheme == 'https' ? 'wss' : 'ws';
    return credential.origin.replace(scheme: scheme, path: path);
  }

  Future<QuWorkGatewayMetadata> metadata(Uri origin) async {
    final value = await _request(origin, 'GET', '/mobile-access/metadata');
    final instanceId = _requiredText(
      value['instanceId'],
      'invalid_gateway_response',
      'Gateway 实例标识缺失',
    );
    final expiry = value['expiresAt'];
    return QuWorkGatewayMetadata(
      origin: origin,
      instanceId: instanceId,
      deviceName: _optionalText(value['deviceName']),
      expiresAt: expiry is num
          ? DateTime.fromMillisecondsSinceEpoch(expiry.toInt())
          : null,
    );
  }

  Future<QuWorkGatewayCredential> pair(
    QuWorkGatewayPairing pairing, {
    String label = 'QuWork 手机',
  }) async {
    if (pairing.caFingerprint == 'required') {
      throw const QuWorkApiException(
        'gateway_ca_pin_required',
        '该 Gateway 使用自签名 CA，当前平台尚未配置证书固定',
      );
    }
    final value = await _request(
      pairing.origin,
      'POST',
      '/mobile-access/auth/native-pair',
      body: {'token': pairing.token, 'label': label},
    );
    return _gatewayCredential(pairing.origin, value, pairing: pairing);
  }

  Future<QuWorkGatewayCredential> renew(
    QuWorkGatewayCredential credential,
  ) async {
    final value = await _request(
      credential.origin,
      'POST',
      '/mobile-access/auth/native-renew',
      body: {'deviceToken': credential.deviceToken},
    );
    return _gatewayCredential(credential.origin, value, previous: credential);
  }

  Future<bool> probe(QuWorkGatewayCredential credential) async {
    try {
      final value = await _request(
        credential.origin,
        'POST',
        '/mobile-access/auth/native-probe',
        body: {'deviceToken': credential.deviceToken},
      );
      final instanceId = _optionalText(value['instanceId']);
      if (credential.instanceId != null && instanceId != credential.instanceId) {
        throw const QuWorkApiException(
          'gateway_instance_mismatch',
          'Gateway 实例已变化，请重新配对',
        );
      }
      return true;
    } on QuWorkApiException catch (error) {
      if (error.code == 'token_expired' || error.statusCode == 401)
        return false;
      rethrow;
    }
  }

  Future<void> logout(QuWorkGatewayCredential credential) async {
    await _request(
      credential.origin,
      'POST',
      '/mobile-access/auth/logout',
      headers: authenticatedHeaders(credential),
      body: {},
    );
  }

  Future<Map<String, Object?>> _request(
    Uri origin,
    String method,
    String path, {
    Map<String, String>? headers,
    Map<String, Object?>? body,
  }) async {
    final uri = origin.replace(
      path: '${origin.path.replaceFirst(RegExp(r'/$'), '')}$path',
    );
    final request = http.Request(method, uri);
    request.headers.addAll({'Accept': 'application/json', ...?headers});
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(response.body);
      final map = _asMap(decoded);
      if (map == null) throw const FormatException();
      if (response.statusCode < 200 || response.statusCode >= 300)
        throw QuWorkApiException(
          response.statusCode == 401 ? 'token_expired' : 'gateway_error',
          _message(map),
          statusCode: response.statusCode,
        );
      return map;
    } on TimeoutException {
      throw const QuWorkApiException('timeout', 'Gateway 请求超时');
    } on http.ClientException catch (error) {
      throw QuWorkApiException('network_unreachable', error.message);
    } on FormatException {
      throw const QuWorkApiException(
        'invalid_gateway_response',
        'Gateway 响应格式无效',
      );
    }
  }

  QuWorkGatewayCredential _gatewayCredential(
    Uri origin,
    Map<String, Object?> value, {
    QuWorkGatewayPairing? pairing,
    QuWorkGatewayCredential? previous,
  }) {
    DateTime epoch(Object? value) => _requiredEpoch(value);
    final session = _requiredText(
      value['sessionToken'],
      'invalid_gateway_response',
      'Gateway 会话缺失',
    );
    final csrf = _requiredText(
      value['csrfToken'],
      'invalid_gateway_response',
      'Gateway CSRF 凭据缺失',
    );
    final id = _requiredText(
      value['deviceId'],
      'invalid_gateway_response',
      'Gateway 设备标识缺失',
    );
    final responseInstance = _optionalText(value['instanceId']);
    if (pairing?.instanceId != null && responseInstance != pairing!.instanceId) {
      throw const QuWorkApiException(
        'gateway_instance_mismatch',
        'Gateway 实例校验失败',
      );
    }
    final device = _optionalText(value['deviceToken']) ?? previous?.deviceToken;
    if (device == null)
      throw const QuWorkApiException(
        'invalid_gateway_response',
        'Gateway 设备凭据缺失',
      );
    return QuWorkGatewayCredential(
      origin: origin,
      deviceId: id,
      deviceToken: device,
      sessionToken: session,
      csrfToken: csrf,
      sessionExpiresAt: epoch(value['sessionExpiresAt']),
      deviceExpiresAt: value['deviceExpiresAt'] == null
          ? previous?.deviceExpiresAt
          : epoch(value['deviceExpiresAt']),
      instanceId:
          _optionalText(value['instanceId']) ??
          pairing?.instanceId ??
          previous?.instanceId,
      caFingerprint: pairing?.caFingerprint ?? previous?.caFingerprint,
    );
  }
}

Uri _origin(Uri uri) => uri.replace(
  path: uri.path.replaceFirst(RegExp(r'/$'), ''),
  query: null,
  fragment: null,
);
Map<String, Object?>? _asMap(Object? value) => value is Map
    ? {for (final entry in value.entries) '${entry.key}': entry.value}
    : null;
String? _optionalText(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;
String _requiredText(Object? value, String code, String message) =>
    _optionalText(value) ?? (throw QuWorkApiException(code, message));
DateTime _requiredEpoch(Object? value) {
  final number = value is num ? value.toInt() : int.tryParse('$value');
  if (number == null || number <= 0) {
    throw const QuWorkApiException('invalid_response', '登录有效期格式无效');
  }
  return DateTime.fromMillisecondsSinceEpoch(
    number < 100000000000 ? number * 1000 : number,
  );
}

bool? _success(Object? value) => switch (value) {
  bool v => v,
  num v => v != 0,
  String v when v == '1' || v.toLowerCase() == 'true' => true,
  String v when v == '0' || v.toLowerCase() == 'false' => false,
  _ => null,
};
String _message(Map<String, Object?> payload) =>
    _optionalText(payload['message']) ?? '请求未完成';
String _errorCode(int status) => status == 401
    ? 'token_expired'
    : status == 429
    ? 'rate_limited'
    : 'service_error';
