import 'dart:io';

Future<void> writeSelectedFile(String path, List<int> bytes) async {
  await File(path).writeAsBytes(bytes, flush: true);
}
