import 'dart:io';
import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';

class ProductImageService {
  const ProductImageService(this.db);
  final AppDatabase db;

  Future<Result<String>> attach({
    required Product product,
    required String sourcePath,
  }) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) {
        return const Failure(
          ValidationFailure('A imagem selecionada não existe.'),
        );
      }
      if (await source.length() > 12 * 1024 * 1024) {
        return const Failure(
          ValidationFailure('A imagem deve ter no máximo 12 MB.'),
        );
      }
      final docs = await getApplicationDocumentsDirectory(),
          extension = sourcePath.split('.').last.toLowerCase();
      final directory = Directory('${docs.path}/product_images')
        ..createSync(recursive: true);
      final path = '${directory.path}/${product.id}.$extension';
      await source.copy(path);
      await (db.update(
        db.products,
      )..where((p) => p.id.equals(product.id))).write(
        ProductsCompanion(
          imagePath: Value(path),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      return Success(path);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível guardar a imagem.', cause: error),
      );
    }
  }
}
