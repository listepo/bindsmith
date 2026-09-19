/// Bumps a semver version: prints the new version to stdout.
///
/// Usage: dart run scripts/bump_version.dart --bump patch|minor|major --current 0.1.0
void main(List<String> args) {
  var bump = 'patch';
  var current = '';
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--bump' && i + 1 < args.length) bump = args[++i];
    if (args[i] == '--current' && i + 1 < args.length) current = args[++i];
  }
  final parts = current.split('.');
  if (parts.length != 3 || parts.any((p) => int.tryParse(p) == null)) {
    throw ArgumentError('Not semver x.y.z: $current');
  }
  var (major, minor, patch) =
      (int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  switch (bump) {
    case 'major':
      major += 1;
      minor = 0;
      patch = 0;
    case 'minor':
      minor += 1;
      patch = 0;
    case 'patch':
      patch += 1;
    default:
      throw ArgumentError('Unknown bump: $bump (patch|minor|major)');
  }
  print('$major.$minor.$patch');
}
