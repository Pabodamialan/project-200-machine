// Non-web fallback for main.dart's conditional import
// (qr_download_stub.dart if (dart.library.html) qr_download_web.dart).
// dart:html only compiles for the web target, so this no-op stub is what
// mobile/desktop builds actually link against — never called in practice,
// since the "Download QR Code" button that calls it is kIsWeb-gated.
void downloadPngBytes(List<int> bytes, String filename) {}
