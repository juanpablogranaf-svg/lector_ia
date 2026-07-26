abstract class Failure {
  final String message;
  const Failure(this.message);
}

class ServerFailure extends Failure {
  final int? statusCode;
  const ServerFailure(super.message, {this.statusCode});
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

class CacheFailure extends Failure {
  const CacheFailure(super.message);
}

class FileSystemFailure extends Failure {
  const FileSystemFailure(super.message);
}

class PermissionFailure extends Failure {
  const PermissionFailure(super.message);
}

class ParsingFailure extends Failure {
  const ParsingFailure(super.message);
}

class ApiKeyMissingFailure extends Failure {
  const ApiKeyMissingFailure() : super('API Key no configurada. Ve a Ajustes para ingresarla.');
}

class RateLimitFailure extends Failure {
  final Duration retryAfter;
  const RateLimitFailure(super.message, {required this.retryAfter});
}
