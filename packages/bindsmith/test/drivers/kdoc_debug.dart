import 'package:bindsmith/src/drivers/jvm/kdoc.dart';

void main() {
  final map = kdocs('''
package example

class Greeter {
  companion object {
    /** the default */
    const val PREFIX = "Hi"
  }
}
''');
  print(map.keys);
}
