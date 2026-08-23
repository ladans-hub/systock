import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/errors/result.dart';

void main() {
  test('Result folds success without exceptions', () {
    const result = Success<int>(42);
    expect(result.fold(success: (value) => value, failure: (_) => -1), 42);
  });
  test('Result exposes a human-safe failure', () {
    const result = Failure<int>(ValidationFailure('Preço inválido.'));
    expect(
      result.fold(success: (_) => '', failure: (error) => error.userMessage),
      'Preço inválido.',
    );
  });
}
