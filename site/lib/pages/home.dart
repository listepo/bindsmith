import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// Minimal landing matching docs/brand/DESIGN.md wire:
/// hero → platform chips → YAML sample → footer.
class Home extends StatelessComponent {
  const Home({super.key});

  static const platforms = [
    'Android',
    'iOS',
    'Web',
    'Windows',
    'macOS',
    'Linux',
  ];

  static const yamlSample = r'''# bindsmith.yaml
package: my_plugin
platforms:
  - android
  - ios
  - web
  - windows
  - macos
  - linux
''';

  @override
  Component build(BuildContext context) {
    return div(classes: 'page', [
      _hero(),
      _platforms(),
      _sample(),
      _footer(),
    ]);
  }

  Component _hero() {
    return header(classes: 'hero', [
      div(classes: 'wrap', [
        img(
          classes: 'hero-mark',
          src: 'images/logo.svg',
          alt: 'bindsmith',
          width: 64,
          height: 64,
        ),
        img(
          classes: 'hero-wordmark',
          src: 'images/logo-wordmark.svg',
          alt: 'bindsmith',
          height: 28,
        ),
        h1(classes: 'hero-pitch', [
          .text('One YAML. Six platforms.'),
        ]),
        p(classes: 'hero-sub', [
          .text(
            'Generate Flutter bindings from a single manifest — forge once, ship everywhere.',
          ),
        ]),
      ]),
    ]);
  }

  Component _platforms() {
    return section(classes: 'platforms', [
      div(classes: 'wrap', [
        p(classes: 'section-label', [.text('Platforms')]),
        div(classes: 'chip-row', [
          for (final name in platforms)
            span(classes: 'chip', [.text(name)]),
        ]),
      ]),
    ]);
  }

  Component _sample() {
    return section(classes: 'sample', [
      div(classes: 'wrap', [
        p(classes: 'section-label', [.text('From YAML to bindings')]),
        div(classes: 'code-card', [
          div(classes: 'code-card-header', [
            span([.text('bindsmith.yaml')]),
            span([.text('placeholder')]),
          ]),
          pre([code([.text(yamlSample)])]),
        ]),
      ]),
    ]);
  }

  Component _footer() {
    return footer(classes: 'footer', [
      div(classes: 'wrap footer-inner', [
        div(classes: 'footer-brand', [
          img(src: 'images/logo.svg', alt: '', width: 24, height: 24),
          span([.text('Listepo / bindsmith')]),
        ]),
        nav(classes: 'footer-links', [
          a(href: 'https://github.com/listepo/bindsmith', [
            .text('GitHub'),
          ]),
          a(href: 'https://github.com/listepo/bindsmith#readme', [
            .text('Docs'),
          ]),
        ]),
      ]),
    ]);
  }
}
