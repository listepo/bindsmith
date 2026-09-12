/// Marks generated code that a human must review before shipping.
///
/// The generator attaches it wherever a mapping was a guess (shape differs
/// between platforms, nullability unknown, TypeScript construct approximated).
/// `bindsmith verify` fails while any annotation remains, unless the config
/// sets `verify.markers: warn` or acknowledges the symbol in `fixups`.
final class BindsmithVerify {
  const BindsmithVerify(this.reason);

  /// Why the generator was unsure, in one sentence.
  final String reason;
}
