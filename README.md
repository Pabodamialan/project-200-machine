# project_200_machine

A new Flutter project.

## Local Web Development — Google Maps API Key

The Google Maps JavaScript API key in `web/index.html` is restricted by
HTTP referrer in Google Cloud Console. `localhost:*` does **not** work as a
"match any port" wildcard — per Google's own API key documentation, the `*`
wildcard is only valid for a subdomain or path segment (e.g.
`*.example.com/*`), never in place of a port number. A port is either
specified exactly (only that port matches) or omitted entirely (any port
matches) — `:*` is neither, so it silently matches nothing, which is why the
Live Tracking map fails with `RefererNotAllowedMapError` even with that
entry present.

**Always run the web app on a fixed port:**

```
flutter run -d chrome --web-port=5000
```

And make sure the Google Cloud Console API key's Website Restrictions list
has this **exact** entry (replace any `localhost:*` entry — it doesn't
match anything and can be removed):

```
localhost:5000
```

If a `flutter run` session is ever left open elsewhere and port 5000 is
already taken, either close that session first or pick a different fixed
port and add the matching `localhost:<port>` entry in the Console — just
keep the port in this command and the port in Console in sync.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
