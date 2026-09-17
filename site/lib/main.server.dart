/// Server / SSG entry — pre-renders the static site.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'app.dart';
import 'main.server.options.dart';

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
    },
    head: [
      link(
        href:
            'https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600&display=swap',
        rel: 'stylesheet',
      ),
      link(href: 'styles/tokens.css', rel: 'stylesheet'),
      link(href: 'styles/landing.css', rel: 'stylesheet'),
      link(href: 'favicon.svg', rel: 'icon', type: 'image/svg+xml'),
    ],
    body: const App(),
  ));
}
