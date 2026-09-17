/// Server / SSG entry — pre-renders the static site.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'app.dart';
import 'main.server.options.dart';

/// FOUC-safe boot: apply stored theme before first paint.
const _themeBoot = r'''
(function () {
  try {
    var KEY = 'bindsmith-theme';
    var pref = localStorage.getItem(KEY) || 'system';
    if (pref !== 'light' && pref !== 'dark' && pref !== 'system') pref = 'system';
    var dark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    var resolved = pref === 'system' ? (dark ? 'dark' : 'light') : pref;
    document.documentElement.setAttribute('data-theme', pref);
    document.documentElement.setAttribute('data-theme-resolved', resolved);
    document.documentElement.style.colorScheme = resolved;
  } catch (e) {
    /* private mode / blocked storage */
  }
})();
''';

void main() {
  Jaspr.initializeApp(options: defaultServerOptions);

  // base: project Pages URL is https://listepo.github.io/bindsmith/
  runApp(Document(
    title: 'bindsmith — One YAML. Six platforms.',
    lang: 'en',
    base: 'bindsmith',
    meta: {
      'description':
          'bindsmith generates Flutter bindings from one YAML to six platforms.',
      'theme-color': '#C87941',
      'color-scheme': 'light dark',
    },
    head: [
      script(content: _themeBoot),
      link(
        href:
            'https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&family=Roboto:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600&display=swap',
        rel: 'stylesheet',
      ),
      link(href: 'styles/tokens.css', rel: 'stylesheet'),
      link(href: 'styles/landing.css', rel: 'stylesheet'),
      link(href: 'favicon.svg', rel: 'icon', type: 'image/svg+xml'),
      script(src: 'js/theme.js', defer: true),
    ],
    body: const App(),
  ));
}
