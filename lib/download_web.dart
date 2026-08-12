import 'dart:html' as html;

void downloadBytes(List<int> bytes, String filename) {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)..setAttribute('download', filename);
  anchor.click();
  html.Url.revokeObjectUrl(url);
}
