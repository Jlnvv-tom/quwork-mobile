import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quwork_api/quwork_api.dart';
import 'package:test/test.dart';

void main() {
  test(
    'uses the One-API phone login session to obtain a QuWork model key',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, anyOf('/api/user/login', '/api/token/'));
        expect(request.headers['X-QurWork-Version'], '1.1.0');
        if (request.url.path == '/api/token/') {
          expect(request.headers['cookie'], 'session=quwork-session');
          return http.Response(
            jsonEncode({
              'success': true,
              'data': [
                {'key': 'model-key', 'status': 1, 'expired_time': -1},
              ],
            }),
            200,
          );
        }
        expect(
          jsonDecode(request.body),
          containsPair('login_type', 'verification_code'),
        );
        return http.Response(
          jsonEncode({
            'success': true,
            'message': '',
            'data': {'id': 7, 'phone': '138****0000'},
          }),
          200,
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'set-cookie': 'session=quwork-session; Path=/; HttpOnly',
          },
        );
      });
      final api = QuWorkAuthApi(
        baseUri: Uri.parse('https://llm.rrzu.com'),
        client: client,
      );
      final result = await api.loginByPhone('13800138000', '123456');
      expect(result.token, isEmpty);
      expect(result.llmToken, 'sk-model-key');
      expect(result.sessionCookie, 'session=quwork-session');
      expect(result.user.id, 7);
    },
  );

  test('puts captcha in the query and form fields in the body', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['aliyun_captcha'], 'captcha');
      expect(
        request.headers['content-type'],
        contains('application/x-www-form-urlencoded'),
      );
      expect(request.body, contains('phone=13800138000'));
      return http.Response(
        jsonEncode({'success': true, 'message': 'ok'}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final api = QuWorkAuthApi(
      baseUri: Uri.parse('https://llm.rrzu.com'),
      client: client,
    );
    expect(
      (await api.sendLoginCode(
        '13800138000',
        aliyunCaptcha: 'captcha',
      )).message,
      'ok',
    );
  });

  test(
    'uses the configured QuWork model base URL for model discovery',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/models');
        expect(request.headers['authorization'], 'Bearer sk-model-key');
        return http.Response(
          jsonEncode({
            'object': 'list',
            'data': [
              {'id': 'quwork-chat', 'owned_by': 'quwork'},
            ],
          }),
          200,
        );
      });
      final api = QuWorkAuthApi(
        baseUri: Uri.parse('https://dev-llm.rrzuji.com'),
        modelBaseUri: Uri.parse('https://dev-llm.rrzuji.com/v1'),
        client: client,
      );
      expect(
        (await api.availableModelDetails('sk-model-key')).single.id,
        'quwork-chat',
      );
    },
  );

  test('normalizes business failure', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({'success': false, 'message': '验证码错误'}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final api = QuWorkAuthApi(
      baseUri: Uri.parse('https://llm.rrzu.com'),
      client: client,
    );
    await expectLater(
      api.loginByPhone('13800138000', 'bad'),
      throwsA(
        isA<QuWorkApiException>().having(
          (e) => e.code,
          'code',
          'service_error',
        ),
      ),
    );
  });

  test(
    'refreshes the One-API session and keeps its model credential',
    () async {
      final client = MockClient((request) async {
        expect(request.headers['cookie'], 'session=quwork-session');
        if (request.url.path == '/api/token/') {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': [
                {'key': 'next-model-token', 'status': 1, 'expired_time': -1},
              ],
            }),
            200,
          );
        }
        expect(request.url.path, '/api/user/self');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'id': 7, 'phone': '138****0000'},
          }),
          200,
        );
      });
      final api = QuWorkAuthApi(
        baseUri: Uri.parse('https://dev-llm.rrzuji.com'),
        client: client,
      );
      api.setSessionCookie('session=quwork-session');
      final result = await api.refresh();
      expect(result.token, isEmpty);
      expect(result.llmToken, 'sk-next-model-token');
    },
  );

  test('parses WeChat login URL and binding-required callback', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/oauth/wechat/url') {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'url': 'https://open.weixin.qq.com/connect/qrconnect?state=s1',
            },
          }),
          200,
        );
      }
      expect(request.url.queryParameters['code'], 'c1');
      expect(request.url.queryParameters['state'], 's1');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {'bind_type': 'need_bind', 'wechat_token': 'one-time'},
        }),
        200,
      );
    });
    final api = QuWorkAuthApi(
      baseUri: Uri.parse('https://llm.rrzu.com'),
      client: client,
    );
    final start = await api.startWechatLogin();
    expect(start.url.host, 'open.weixin.qq.com');
    final result = await api.finishWechatLogin(
      Uri.parse('https://llm.rrzu.com/callback?code=c1&state=s1'),
    );
    expect(result.requiresBinding, isTrue);
    expect(result.wechatToken, 'one-time');
  });

  test(
    'parses native Gateway pairing QR and stores native credentials',
    () async {
      final pairing = QuWorkGatewayPairing.fromQr(
        Uri.parse(
          'https://host.example/mobile-access/pair#instance=i-1&token=pair-token',
        ),
      );
      expect(pairing.instanceId, 'i-1');
      final client = MockClient((request) async {
        expect(request.url.path, '/mobile-access/auth/native-pair');
        expect(jsonDecode(request.body), containsPair('token', 'pair-token'));
        return http.Response(
          jsonEncode({
            'instanceId': 'i-1',
            'deviceId': 'a' * 32,
            'deviceToken': 'device',
            'deviceExpiresAt': 1791714075000,
            'sessionToken': 'session',
            'csrfToken': 'csrf',
            'sessionExpiresAt': 1791714075000,
          }),
          201,
        );
      });
      final api = QuWorkGatewayApi(client: client);
      final credential = await api.pair(pairing);
      expect(credential.deviceId, 'a' * 32);
      expect(
        QuWorkGatewayCredential.fromJson(credential.toJson()).csrfToken,
        'csrf',
      );
    },
  );
}
