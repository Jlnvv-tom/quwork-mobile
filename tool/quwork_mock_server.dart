import 'dart:convert';
import 'dart:io';

/// Offline contract fixture for simulator work. It deliberately returns fake
/// credentials and models; it never calls the real QuWork service.
Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, int.parse(Platform.environment['PORT'] ?? '8787'));
  stdout.writeln('QuWork mock listening on http://${server.address.host}:${server.port}');
  await for (final request in server) {
    try {
      await _handle(request);
    } catch (error) {
      request.response.statusCode = 500;
      request.response.write(jsonEncode({'success': false, 'message': '$error'}));
      await request.response.close();
    }
  }
}

Future<void> _handle(HttpRequest request) async {
  final path = request.uri.path;
  if (request.method == 'POST' && path == '/api/sendVerifyCode') {
    return _json(request, {'success': true, 'message': 'mock code: 123456', 'data': null});
  }
  if (request.method == 'POST' && path == '/api/user/client/login') {
    final body = await _body(request);
    if (body['verification_code'] != '123456') return _json(request, {'success': false, 'message': '验证码错误'});
    return _json(request, {'success': true, 'message': '', 'data': {
      'token': 'mock-jwt', 'expire': DateTime.now().add(const Duration(hours: 12)).millisecondsSinceEpoch,
      'llm_token': 'mock-llm-token', 'user': {'id': 1, 'phone': body['phone'] ?? '13800138000', 'display_name': '模拟账号', 'wechat_bound': false},
    }});
  }
  if (request.method == 'GET' && path == '/api/user/self') {
    return _json(request, {'success': true, 'data': {'id': 1, 'phone': '13800138000', 'display_name': '模拟账号', 'wechat_bound': false}});
  }
  if (request.method == 'GET' && path == '/api/user/refresh') {
    return _json(request, {'success': true, 'data': {'token': 'mock-jwt-rotated', 'expire': DateTime.now().add(const Duration(hours: 12)).millisecondsSinceEpoch}});
  }
  if (request.method == 'GET' && path == '/api/user/available_models') {
    return _json(request, {'success': true, 'data': ['deepseek-chat', 'deepseek-reasoner']});
  }
  if (request.method == 'GET' && path == '/api/oauth/wechat/url') {
    return _json(request, {'success': true, 'data': {'url': 'https://open.weixin.qq.com/connect/qrconnect?state=mock-state', 'state': 'mock-state'}});
  }
  if (request.method == 'GET' && path == '/api/oauth/wechat') {
    return _json(request, {'success': false, 'message': 'wechat_bind_required', 'data': {'bind_type': 'need_bind', 'wechat_token': 'mock-wechat-token'}});
  }
  if (request.method == 'POST' && path == '/api/user/wechat/bind') {
    return _json(request, {'success': true, 'data': null});
  }
  if (request.method == 'GET' && path == '/api/user/logout') {
    return _json(request, {'success': true, 'data': null});
  }
  if (request.method == 'GET' && (path == '/v1/models' || path == '/models')) {
    return _json(request, {'object': 'list', 'data': [
      {'id': 'deepseek-chat', 'object': 'model', 'owned_by': 'quwork-mock'},
      {'id': 'deepseek-reasoner', 'object': 'model', 'owned_by': 'quwork-mock'},
    ]});
  }
  if (request.method == 'POST' && (path == '/v1/chat/completions' || path == '/chat/completions')) {
    final body = await _body(request);
    final model = body['model'] ?? 'deepseek-chat';
    return _json(request, {'id': 'mock-completion', 'object': 'chat.completion', 'model': model, 'choices': [
      {'index': 0, 'message': {'role': 'assistant', 'content': '本地 QuWork mock 已收到消息。'}, 'finish_reason': 'stop'},
    ], 'usage': {'prompt_tokens': 1, 'completion_tokens': 8, 'total_tokens': 9}});
  }
  if (request.method == 'GET' && path == '/mobile-access/metadata') {
    return _json(request, {'version': 'mock', 'instanceId': 'mock-instance', 'pluginVersion': 'mock'});
  }
  if (request.method == 'POST' && path == '/mobile-access/auth/native-pair') {
    return _json(request, {'instanceId': 'mock-instance', 'deviceId': 'b' * 32, 'deviceToken': 'mock-device-token', 'deviceExpiresAt': DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch, 'sessionToken': 'mock-session-token', 'csrfToken': 'mock-csrf-token', 'sessionExpiresAt': DateTime.now().add(const Duration(hours: 12)).millisecondsSinceEpoch});
  }
  if (request.method == 'POST' && path == '/mobile-access/auth/native-renew') {
    return _json(request, {'instanceId': 'mock-instance', 'deviceId': 'b' * 32, 'sessionToken': 'mock-session-token-2', 'csrfToken': 'mock-csrf-token-2', 'sessionExpiresAt': DateTime.now().add(const Duration(hours: 12)).millisecondsSinceEpoch});
  }
  if (request.method == 'POST' && path == '/mobile-access/auth/native-probe') {
    return _json(request, {'instanceId': 'mock-instance', 'deviceId': 'b' * 32, 'deviceExpiresAt': DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch});
  }
  if (request.method == 'POST' && path == '/mobile-access/auth/logout') {
    return _json(request, {'loggedOut': true});
  }
  request.response.statusCode = 404;
  return _json(request, {'success': false, 'message': 'not_found'});
}

Future<Map<String, Object?>> _body(HttpRequest request) async {
  final raw = await utf8.decoder.bind(request).join();
  final decoded = jsonDecode(raw);
  return decoded is Map ? {for (final entry in decoded.entries) '${entry.key}': entry.value} : {};
}

Future<void> _json(HttpRequest request, Map<String, Object?> body) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}
