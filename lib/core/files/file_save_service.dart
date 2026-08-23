import 'dart:typed_data';
import 'package:file_picker/file_picker.dart' as picker;
import 'package:systock/core/errors/result.dart';

class FileSaveService {
  const FileSaveService();

  Future<Result<Uri?>> save({
    required String dialogTitle,
    required String fileName,
    required List<int> bytes,
    required String mimeType,
  }) async {
    try {
      final uri = await picker.FilePicker.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        bytes: Uint8List.fromList(bytes),
        mimeType: mimeType,
      );
      return Success(uri);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível guardar o arquivo.', cause: error),
      );
    }
  }
}
