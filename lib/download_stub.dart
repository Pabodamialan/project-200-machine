// Non-web fallback for lib/download_web.dart. ManagementSiteReportsScreen is
// only reachable on web (see AuthGate/ManagementDashboard), so this is never
// actually called on mobile — it only needs to exist so mobile builds
// compile, since dart:html isn't available there.
void downloadBytes(List<int> bytes, String filename) {}
