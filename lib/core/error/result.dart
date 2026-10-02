import 'app_failure.dart';

sealed class Result<T> {
  const Result();

  R when<R>({required R Function(T value) ok, required R Function(AppFailure failure) err}) =>
      switch (this) {
        Ok<T>(:final value) => ok(value),
        Err<T>(:final failure) => err(failure),
      };

  /// The value when this is an [Ok], else null.
  T? get valueOrNull => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => null,
      };

  /// The failure when this is an [Err], else null.
  AppFailure? get failureOrNull => switch (this) {
        Ok<T>() => null,
        Err<T>(:final failure) => failure,
      };
}

class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

class Err<T> extends Result<T> {
  const Err(this.failure);
  final AppFailure failure;
}
