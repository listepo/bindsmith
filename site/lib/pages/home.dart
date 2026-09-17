import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// Material 3 landing — copper seed, FAB+braces mark, tonal surfaces.
/// Sections: AppBar, hero, platforms, CLI, YAML, features, NavigationBar, footer.
class Home extends StatelessComponent {
  const Home({super.key});

  static const platforms = [
    ('Android', 'android'),
    ('iOS', 'ios'),
    ('Web', 'web'),
    ('Windows', 'windows'),
    ('macOS', 'macos'),
    ('Linux', 'linux'),
  ];

  static const features = [
    (
      '01',
      'one yaml',
      'Declare platforms once in a single manifest — no per-target boilerplate sprawl.',
    ),
    (
      '02',
      'six targets',
      'Android, iOS, Web, Windows, macOS, Linux bindings from the same source of truth.',
    ),
    (
      '03',
      'cli first',
      'Nerd-friendly generate flow: `bindsmith generate` and ship. Mono logs, clear exits.',
    ),
    (
      '04',
      'material native',
      'Built for Flutter/Dart plugin authors — M3 tonal UI, copper primary, azure secondary.',
    ),
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
      _appBar(),
      _hero(),
      _platforms(),
      _sample(),
      _features(),
      _footer(),
      _navBar(),
    ]);
  }

  Component _appBar() {
    return header(classes: 'top m3-appbar', [
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
            a(href: '#features', [.text('Features')]),
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
          width: 72,
          height: 72,
        ),
        p(classes: 'hero-wordmark-text', [.text('bindsmith')]),
        div(classes: 'hero-meta', [
          span(classes: 'status-chip', [.text('m3 ready')]),
          span(classes: 'badge badge-flutter', [.text('Flutter')]),
          span(classes: 'badge badge-dart', [.text('Dart')]),
          span(classes: 'badge badge-m3', [.text('Material 3')]),
        ]),
        h1(classes: 'hero-pitch', [
          .text('One YAML. Six platforms.'),
        ]),
        p(classes: 'hero-sub', [
          .text(
            'Generate Flutter bindings from a single manifest — Material 3 tonal surfaces, copper primary, nerd CLI density.',
          ),
        ]),
        div(classes: 'cta-row', [
          a(
            classes: 'cta cta-filled',
            href: 'https://github.com/listepo/bindsmith',
            [.text('Get started')],
          ),
          a(classes: 'cta cta-tonal', href: '#cli', [.text('See the CLI')]),
          a(
            classes: 'cta cta-outlined',
            href: '#platforms',
            [.text('Platforms')],
          ),
        ]),
      ]),
    ]);
  }

  Component _platforms() {
    return section(classes: 'platforms', id: 'platforms', [
      div(classes: 'wrap wrap-wide', [
        p(classes: 'section-label', [.text('Platforms')]),
        p(classes: 'section-lead', [
          .text('Six targets. One manifest. Surface-container cards with M3 density.'),
        ]),
        div(classes: 'platform-grid', [
          for (final (name, slug) in platforms)
            div(classes: 'platform-card m3-card', [
              span(classes: 'platform-pip', attributes: {'data-platform': slug}, []),
              span(classes: 'platform-name', [.text(name)]),
              span(classes: 'platform-slug', [.text(slug)]),
            ]),
        ]),
      ]),
    ]);
  }

  Component _sample() {
    return section(classes: 'sample', id: 'cli', [
      div(classes: 'wrap card-stack', [
        p(classes: 'section-label', [.text('Generate')]),
        p(classes: 'section-lead', [
          .text('CLI first — then the YAML that drives every platform bind.'),
        ]),
        div(classes: 'code-card m3-card', id: 'cli-card', [
          div(classes: 'code-card-header', [
            span([.text('terminal')]),
            span(classes: 'tag', [.text('CLI')]),
          ]),
          pre([
            code([
              RawText(
                '<span class="prompt">\$</span> bindsmith generate\n'
                '<span class="dim"># → platform bindings from one YAML</span>\n'
                '<span class="ok">✓</span> android  ios  web  windows  macos  linux\n',
              ),
            ]),
          ]),
        ]),
        div(classes: 'code-card m3-card', id: 'yaml', [
          div(classes: 'code-card-header', [
            span([.text('bindsmith.yaml')]),
            span(classes: 'tag', [.text('manifest')]),
          ]),
          pre([code([.text(yamlSample)])]),
        ]),
      ]),
    ]);
  }

  Component _features() {
    return section(classes: 'features', id: 'features', [
      div(classes: 'wrap wrap-wide', [
        p(classes: 'section-label', [.text('Features')]),
        div(classes: 'feature-grid', [
          for (final (num, title, body) in features)
            div(classes: 'feature-card m3-card', [
              span(classes: 'feature-num', [.text(num)]),
              h3(classes: 'feature-title', [.text(title)]),
              p(classes: 'feature-body', [.text(body)]),
            ]),
        ]),
      ]),
    ]);
  }

  Component _navBar() {
    return nav(
      classes: 'm3-nav-bar',
      attributes: {'aria-label': 'Mobile'},
      [
        div(classes: 'm3-nav-bar-inner', [
          a(classes: 'm3-nav-item is-active', href: './', attributes: {'aria-current': 'page'}, [
            span(classes: 'm3-nav-icon', [.text('⌂')]),
            span([.text('Home')]),
          ]),
          a(classes: 'm3-nav-item', href: '#platforms', [
            span(classes: 'm3-nav-icon', [.text('▦')]),
            span([.text('Targets')]),
          ]),
          a(classes: 'm3-nav-item', href: '#cli', [
            span(classes: 'm3-nav-icon', [.text('>_')]),
            span([.text('CLI')]),
          ]),
          a(classes: 'm3-nav-item', href: '#features', [
            span(classes: 'm3-nav-icon', [.text('✦')]),
            span([.text('More')]),
          ]),
        ]),
      ],
    );
  }

  Component _footer() {
    return footer(classes: 'footer', [
      div(classes: 'wrap footer-inner', [
        div(classes: 'footer-brand', [
          img(src: 'images/logo.svg', alt: '', width: 28, height: 28),
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
