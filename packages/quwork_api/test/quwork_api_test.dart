import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quwork_api/quwork_api.dart';
import 'package:test/test.dart';

void main() {
  test(
    'sends the phone login contract and parses optional llm token',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/user/client/login');
        expect(request.headers['X-QurWork-Version'], '1.1.0');
        expect(jsonDecode(request.body), containsPair('platform', 'qurvis'));
        return http.Response(
          jsonEncode({
            'success': true,
            'message': '',
            'data': {
              'token': 'jwt',
              'expire': 1791714075,
              'llm_token': '',
              'user': {'id': 7, 'phone': '138****0000'},
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final api = QuWorkAuthApi(
        baseUri: Uri.parse('https://llm.rrzu.com'),
        client: client,
      );
      final result = await api.loginByPhone('13800138000', '123456');
      expect(result.token, 'jwt');
      expect(result.llmToken, isNull);
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

  test('keeps a refreshed model credential when the refresh response includes it', () async {
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer access-token');
      if (request.url.path == '/api/user/refresh') {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'token': 'next-access-token',
              'expire': 1791714075,
              'llm_token': 'next-llm-token',
            },
          }),
          200,
        );
      }
      expect(request.url.path, '/api/user/self');
      return http.Response(
        jsonEncode({'success': true, 'data': {'id': 7, 'phone': '138****0000'}}),
        200,
      );
    });
    final api = QuWorkAuthApi(
      baseUri: Uri.parse('https://dev-llm.rrzuji.com'),
      client: client,
    );
    final result = await api.refresh('access-token');
    expect(result.token, 'next-access-token');
    expect(result.llmToken, 'next-llm-token');
  });

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
