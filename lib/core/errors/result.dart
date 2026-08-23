sealed class Result<T> {
  const Result();
  R fold<R>({
    required R Function(T) success,
    required R Function(AppFailure) failure,
  }) => switch (this) {
    Success<T>(:final value) => success(value),
    Failure<T>(:final error) => failure(error),
  };
}

final class Success<T> extends Result<T> {
  const Success(this.value);
  final T value;
}

final class Failure<T> extends Result<T> {
  const Failure(this.error);
  final AppFailure error;
}

sealed class AppFailure {
  const AppFailure(this.userMessage, {this.cause});
  final String userMessage;
  final Object? cause;
}

final class ValidationFailure extends AppFailure {
  const ValidationFailure(super.userMessage);
}

final class StorageFailure extends AppFailure {
  const StorageFailure(super.userMessage, {super.cause});
}

final class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure(super.userMessage, {super.cause});
}
