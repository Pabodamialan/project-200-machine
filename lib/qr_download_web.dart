// Web implementation for main.dart's conditional import — see
// qr_download_stub.dart for the non-web fallback this replaces on web
// builds. Standard Blob + object URL + AnchorElement.click() download
// pattern; there's no existing one elsewhere in this codebase to reuse
// (Excel export downloads via the `excel` package's own internal
// SavingHelper, not anything of ours), so this is a fresh, minimal
// implementation of it.
import 'dart:html' as html;

void downloadPngBytes(List<int> bytes, String filename) {
  final blob = html.Blob([bytes], 'image/png');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
