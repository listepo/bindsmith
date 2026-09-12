import 'platform.dart';

/// Thrown by a generated facade when [symbol] has no implementation on
/// [platform] and the config asked for `unsupported: throw`.
final class BindsmithUnsupported extends UnsupportedError {
  BindsmithUnsupported(this.symbol, this.platform)
    : super('$symbol is not available on ${platform.name}');

  /// Dart-facing name of the missing symbol, e.g. `Client.connect`.
  final String symbol;

  /// Platform the program is running on.
  final BindsmithPlatform platform;
}
