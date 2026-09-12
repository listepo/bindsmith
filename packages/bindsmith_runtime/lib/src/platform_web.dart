import 'platform.dart';

/// The platform this program is running on. Compiled with dart2js or
/// dart2wasm, that is always the browser.
BindsmithPlatform get bindsmithPlatform => BindsmithPlatform.web;
