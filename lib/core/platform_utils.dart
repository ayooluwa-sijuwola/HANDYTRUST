// Conditional export: the dart:io implementation when available, otherwise the web stub.

// Re-exported getter
export 'platform_io.dart' if (dart.library.html) 'platform_web.dart';
