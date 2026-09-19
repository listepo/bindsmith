/// The annotations generated facades use: what still needs a human, and how to
/// dispatch on the current platform.
///
/// ```dart
/// String greet(BindsmithPlatform platform) => switch (platform) {
///   BindsmithPlatform.android => 'hi',
///   _ => throw const BindsmithUnsupported('greet', BindsmithPlatform.linux),
/// };
/// ```
library;

void main() {}
