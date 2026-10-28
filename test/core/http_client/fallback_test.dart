import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';

void main() {
  DioHttpClient client(int proxyPort) {
    final client = DioHttpClient(timeout: const Duration(seconds: 5), userAgent: 'test-agent', debug: false);
    client.setProxyPort(proxyPort);
    return client;
  }

  Future<int> unusedPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  test(
    'a proxy that accepts the connection and drops it falls back to the direct request',
    () async {
      final hits = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((request) {
          hits.add(request.uri.path);
          request.response
            ..write('direct')
            ..close();
        }),
      );
      // the tunnel is up with no working proxy: the port answers, then the connection is closed
      final deadProxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(deadProxy.close);
      unawaited(deadProxy.forEach((socket) => socket.destroy()));

      final response = await client(deadProxy.port).get<String>('http://127.0.0.1:${server.port}/sub');

      expect(response.data, 'direct');
      expect(hits, ['/sub']);
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test('a direct request that cannot reach the host falls back to the proxy', () async {
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => proxy.close(force: true));
    unawaited(
      proxy.forEach((request) {
        request.response
          ..write('via proxy')
          ..close();
      }),
    );
    final unreachable = await unusedPort();

    final response = await client(proxy.port).get<String>('http://127.0.0.1:$unreachable/sub', forceDirect: true);

    expect(response.data, 'via proxy');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('a server that answers with an error is not asked again through the other way', () async {
    var served = 0;
    var proxied = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(
      server.forEach((request) {
        served++;
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
      }),
    );
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => proxy.close(force: true));
    unawaited(
      proxy.forEach((request) {
        proxied++;
        request.response.close();
      }),
    );

    await expectLater(
      client(proxy.port).get<String>('http://127.0.0.1:${server.port}/sub', forceDirect: true),
      throwsA(isA<DioException>().having((error) => error.type, 'type', DioExceptionType.badResponse)),
    );

    expect(served, 1);
    expect(proxied, 0);
  });

  test('a request limited to the proxy does not fall back to a direct one', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var direct = 0;
    unawaited(
      server.forEach((request) {
        direct++;
        request.response.close();
      }),
    );
    final deadProxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(deadProxy.close);
    unawaited(deadProxy.forEach((socket) => socket.destroy()));

    await expectLater(
      client(deadProxy.port).get<String>('http://127.0.0.1:${server.port}/sub', proxyOnly: true),
      throwsA(isA<DioException>()),
    );

    expect(direct, 0);
  }, timeout: const Timeout(Duration(seconds: 40)));
}
