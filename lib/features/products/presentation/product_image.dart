import 'dart:io';
import 'package:flutter/material.dart';

class ProductImage extends StatelessWidget {
  const ProductImage({
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 8,
    super.key,
  });

  final String? path;
  final double? width, height;
  final BoxFit fit;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final value = path;
    Widget image;
    if (value == null || value.isEmpty) {
      image = ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.inventory_2_outlined)),
      );
    } else if (value.startsWith('asset://')) {
      image = Image.asset(
        value.substring('asset://'.length),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) =>
            const Center(child: Icon(Icons.broken_image_outlined)),
      );
    } else {
      image = Image.file(
        File(value),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) =>
            const Center(child: Icon(Icons.broken_image_outlined)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(width: width, height: height, child: image),
    );
  }
}
