import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// Minimal landing matching docs/brand/DESIGN.md wire:
/// top bar + theme → hero → platform chips → CLI/YAML → footer.
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

  static const _iconSun = '''
<svg class="theme-toggle-icon icon-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">
  <circle cx="12" cy="12" r="4"></circle>
  <path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"></path>
</svg>''';

  static const _iconMoon = '''
<svg class="theme-toggle-icon icon-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">
  <path d="M21 14.5A8.5 8.5 0 1 1 9.5 3a7 7 0 0 0 11.5 11.5z"></path>
</svg>''';

  static const _iconSystem = '''
<svg class="theme-toggle-icon icon-system" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">
  <rect x="3" y="4" width="18" height="12" rx="2"></rect>
  <path d="M8 20h8M12 16v4"></path>
</svg>''';

  @override
  Component build(BuildContext context) {
    return div(classes: 'page', [
      _top(),
      _hero(),
      _platforms(),
      _sample(),
      _footer(),
    ]);
  }

  Component _top() {
    return header(classes: 'top', [
      div(classes: 'wrap top-inner', [
        a(classes: 'brand', href: './', [
          img(src: 'images/logo.svg', alt: '', width: 32, height: 32),
          span(classes: 'brand-name', [.text('bindsmith')]),
        ]),
        div(classes: 'header-actions', [
          nav(classes: 'nav', attributes: {'aria-label': 'Primary'}, [
            a(href: 'https://github.com/listepo/bindsmith', [.text('GitHub')]),
            a(href: '#platforms', [.text('Platforms')]),
            a(href: '#cli', [.text('CLI')]),
          ]),
          button(
            [
              RawText(_iconSun),
              RawText(_iconMoon),
              RawText(_iconSystem),
              span(attributes: {'data-theme-label': ''}, [.text('system')]),
            ],
            type: ButtonType.button,
            id: 'theme-toggle',
            classes: 'theme-toggle',
            attributes: {
              'data-theme': 'system',
              'aria-label': 'Theme: system (follows OS)',
              'title': 'Cycle theme: system → light → dark',
            },
          ),
        ]),
      ]),
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
        div(classes: 'hero-meta', [
          span(classes: 'status-chip', [.text('forge ready')]),
        ]),
        h1(classes: 'hero-pitch', [
          .text('One YAML. Six platforms.'),
        ]),
        p(classes: 'hero-sub', [
          .text(
            'Generate Flutter bindings from a single manifest — forge once, ship everywhere.',
          ),
        ]),
        div(classes: 'cta-row', [
          a(
            classes: 'cta',
            href: 'https://github.com/listepo/bindsmith',
            [.text('forge')],
          ),
          a(classes: 'ghost', href: '#cli', [.text('see the CLI')]),
        ]),
      ]),
    ]);
  }

  Component _platforms() {
    return section(classes: 'platforms', id: 'platforms', [
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
    return section(classes: 'sample', id: 'cli', [
      div(classes: 'wrap card-stack', [
        p(classes: 'section-label', [.text('From YAML to bindings')]),
        div(classes: 'code-card', [
          div(classes: 'code-card-header', [
            span([.text('terminal')]),
            span(classes: 'tag', [.text('CLI')]),
          ]),
          pre([
            code([
              RawText(
                '<span class="prompt">\$</span> bindsmith generate\n'
                '<span class="dim"># → platform bindings from one YAML</span>\n',
              ),
            ]),
          ]),
        ]),
        div(classes: 'code-card', [
          div(classes: 'code-card-header', [
            span([.text('bindsmith.yaml')]),
            span(classes: 'tag', [.text('manifest')]),
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
