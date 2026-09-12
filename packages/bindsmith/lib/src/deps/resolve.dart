/// Resolves every dependency kind bindsmith knows about into lockfile sections.
library;

import 'dart:io';

import 'lockfile.dart';
import 'maven.dart';
import 'npm.dart';
import 'nuget.dart';

/// Collects pinned artifacts for npm and nuget from platform dependency lists.
///
/// [npmPackages] and [nugetPackages] are the union of every configured
/// `deps.npm` / `deps.nuget` entry — the caller deduplicates across platforms.
Future<Map<String, List<LockedArtifact>>> resolveNpmAndNuget({
  required Iterable<String> npmPackages,
  required Iterable<String> nugetPackages,
  required Directory npmCache,
  required Directory nugetCache,
  required bool offline,
}) async {
  final artifacts = <String, List<LockedArtifact>>{};
  if (npmPackages.isNotEmpty) {
    artifacts['npm'] = await resolveNpm(
      packages: npmPackages,
      cache: npmCache,
      fetch: offline
          ? (url) => throw NpmException(
              '$url is not in the download cache, and --offline forbids '
              'fetching it. Resolve once with a network first.',
            )
          : null,
    );
  }
  if (nugetPackages.isNotEmpty) {
    artifacts['nuget'] = await resolveNuget(
      packages: nugetPackages,
      cache: nugetCache,
      fetch: offline
          ? (url) => throw NugetException(
              '$url is not in the download cache, and --offline forbids '
              'fetching it. Resolve once with a network first.',
            )
          : null,
    );
  }
  return artifacts;
}

/// Collects pinned artifacts for every dependency kind in one map.
///
/// Intended call site inside `runner.dart` `_resolve` after the existing Maven
/// loop:
///
/// ```dart
/// final extra = await resolveAllDeps(
///   mavenCoordinates: [
///     for (final platform in project.platforms)
///       ...project.config.platforms[platform]!.deps.maven
///           .map((coordinate) => coordinate.toString()),
///   ],
///   npmPackages: [
///     for (final platform in project.platforms)
///       ...project.config.platforms[platform]!.deps.npm,
///   ],
///   nugetPackages: [
///     for (final platform in project.platforms)
///       ...project.config.platforms[platform]!.deps.nuget,
///   ],
///   mavenCache: cache,
///   npmCache: Directory(p.join(project.root, '.dart_tool', 'bindsmith', 'npm')),
///   nugetCache:
///       Directory(p.join(project.root, '.dart_tool', 'bindsmith', 'nuget')),
///   offline: offline,
///   mavenRepositories: project.config.platforms[project.platforms.first]!
///       .deps.repositories, // or per-platform merge as today
/// );
/// return Lockfile({
///   if (maven.isNotEmpty) 'maven': maven.values.toList(),
///   ...extra,
/// });
/// ```
Future<Map<String, List<LockedArtifact>>> resolveAllDeps({
  required Iterable<String> mavenCoordinates,
  required Iterable<String> npmPackages,
  required Iterable<String> nugetPackages,
  required Directory mavenCache,
  required Directory npmCache,
  required Directory nugetCache,
  required bool offline,
  List<Uri>? mavenRepositories,
}) async {
  final artifacts = <String, List<LockedArtifact>>{};

  final maven = <String, LockedArtifact>{};
  if (mavenCoordinates.isNotEmpty) {
    final resolver = MavenResolver(
      cache: mavenCache,
      repositories: mavenRepositories,
      fetch: offline
          ? (url) => throw MavenException(
              '$url is not in the download cache, and --offline forbids '
              'fetching it. Resolve once with a network first.',
            )
          : mavenFetch,
    );
    for (final artifact in await resolver.resolve(mavenCoordinates)) {
      maven['${artifact.coordinate}'] = (
        coordinate: '${artifact.coordinate}',
        extension: artifact.extension,
        sha256: artifact.sha256,
      );
    }
    artifacts['maven'] = maven.values.toList();
  }

  artifacts.addAll(
    await resolveNpmAndNuget(
      npmPackages: npmPackages,
      nugetPackages: nugetPackages,
      npmCache: npmCache,
      nugetCache: nugetCache,
      offline: offline,
    ),
  );

  return artifacts;
}
