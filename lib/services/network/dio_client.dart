import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class DioClient {
  static Dio create() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException e, handler) async {
          if (_shouldRetry(e)) {
            int retryCount =
                (e.requestOptions.extra['retry_count'] ?? 0) as int;
            if (retryCount < 3) {
              e.requestOptions.extra['retry_count'] = retryCount + 1;

              // Wait a bit before retry
              await Future.delayed(Duration(seconds: 1 * (retryCount + 1)));

              try {
                final response = await dio.fetch(e.requestOptions);
                return handler.resolve(response);
              } catch (retryError) {
                // If retry fails, continue to next interceptor or return error
                if (retryError is DioException) {
                  return handler.next(retryError);
                }
                return handler.next(e);
              }
            }
          }
          return handler.next(e);
        },
      ),
    );

    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
      ));
    }

    return dio;
  }

  static bool _shouldRetry(DioException e) {
    return e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout;
  }
}
