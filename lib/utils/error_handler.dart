// Error handling and logging

class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalException;

  AppException({
    required this.message,
    this.code,
    this.originalException,
  });

  @override
  String toString() => message;
}

class NetworkException extends AppException {
  NetworkException({
    String message = 'Network error occurred',
    String? code,
    dynamic originalException,
  }) : super(
    message: message,
    code: code ?? 'NETWORK_ERROR',
    originalException: originalException,
  );
}

class DatabaseException extends AppException {
  DatabaseException({
    String message = 'Database error occurred',
    String? code,
    dynamic originalException,
  }) : super(
    message: message,
    code: code ?? 'DATABASE_ERROR',
    originalException: originalException,
  );
}

class ApiException extends AppException {
  final int? statusCode;

  ApiException({
    required String message,
    this.statusCode,
    String? code,
    dynamic originalException,
  }) : super(
    message: message,
    code: code ?? 'API_ERROR',
    originalException: originalException,
  );
}

class ValidationException extends AppException {
  ValidationException({
    required String message,
    String? code,
    dynamic originalException,
  }) : super(
    message: message,
    code: code ?? 'VALIDATION_ERROR',
    originalException: originalException,
  );
}

class Logger {
  static const String _tag = 'VodafoneCashTracker';
  static bool _debugMode = true;

  static void setDebugMode(bool debug) {
    _debugMode = debug;
  }

  static void log(String message, {String? tag}) {
    if (_debugMode) {
      print('[$_tag${tag != null ? ':$tag' : ''}] $message');
    }
  }

  static void logError(String message, {String? tag, dynamic error, StackTrace? stackTrace}) {
    if (_debugMode) {
      print('[$_tag${tag != null ? ':$tag' : ''}] ERROR: $message');
      if (error != null) {
        print('Error: $error');
      }
      if (stackTrace != null) {
        print('StackTrace: $stackTrace');
      }
    }
  }

  static void logWarning(String message, {String? tag}) {
    if (_debugMode) {
      print('[$_tag${tag != null ? ':$tag' : ''}] WARNING: $message');
    }
  }

  static void logInfo(String message, {String? tag}) {
    if (_debugMode) {
      print('[$_tag${tag != null ? ':$tag' : ''}] INFO: $message');
    }
  }

  static void logDebug(String message, {String? tag}) {
    if (_debugMode) {
      print('[$_tag${tag != null ? ':$tag' : ''}] DEBUG: $message');
    }
  }

  // API Logging
  static void logApiRequest(String method, String url, {Map<String, dynamic>? headers, dynamic body}) {
    if (_debugMode) {
      print('[$_tag:API] REQUEST: $method $url');
      if (headers != null) {
        print('Headers: $headers');
      }
      if (body != null) {
        print('Body: $body');
      }
    }
  }

  static void logApiResponse(String method, String url, int statusCode, {dynamic response}) {
    if (_debugMode) {
      print('[$_tag:API] RESPONSE: $method $url - Status: $statusCode');
      if (response != null) {
        print('Response: $response');
      }
    }
  }

  // Database Logging
  static void logDatabaseOperation(String operation, String path, {dynamic data}) {
    if (_debugMode) {
      print('[$_tag:DB] $operation: $path');
      if (data != null) {
        print('Data: $data');
      }
    }
  }
}

class ResultWrapper<T> {
  final T? data;
  final AppException? error;
  final bool isSuccess;

  ResultWrapper({
    this.data,
    this.error,
  }) : isSuccess = error == null;

  factory ResultWrapper.success(T data) {
    return ResultWrapper(data: data);
  }

  factory ResultWrapper.error(AppException error) {
    return ResultWrapper(error: error);
  }

  /// Execute callback based on result
  void when({
    required Function(T data) onSuccess,
    required Function(AppException error) onError,
  }) {
    if (isSuccess && data != null) {
      final d = data as T;
      onSuccess(d);
    } else if (error != null) {
      onError(error!);
    }
  }

  /// Map result to another type
  ResultWrapper<U> map<U>(U Function(T) transform) {
    if (isSuccess && data != null) {
      final d = data as T;
      return ResultWrapper.success(transform(d));
    } else {
      return ResultWrapper.error(error!);
    }
  }

  /// Flat map result
  ResultWrapper<U> flatMap<U>(ResultWrapper<U> Function(T) transform) {
    if (isSuccess && data != null) {
      final d = data as T;
      return transform(d);
    } else {
      return ResultWrapper.error(error!);
    }
  }
}
