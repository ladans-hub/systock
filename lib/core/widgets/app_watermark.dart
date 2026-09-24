import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/database_provider.dart';

class CompanyWatermarkLogo extends ConsumerWidget {
  const CompanyWatermarkLogo({this.size = 112, this.opacity = .08, super.key});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context, WidgetRef ref) => StreamBuilder<String?>(
    stream: _companyLogoStream(ref),
    builder: (context, snapshot) {
      final logoPath = snapshot.data;
      final hasCompanyLogo = logoPath != null && File(logoPath).existsSync();
      return IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: SizedBox.square(
            dimension: size,
            child: hasCompanyLogo
                ? Image.file(File(logoPath), fit: BoxFit.contain)
                : Image.asset(
                    'assets/branding/systock_logo_transparent.png',
                    fit: BoxFit.contain,
                  ),
          ),
        ),
      );
    },
  );
}

class AppWatermark extends ConsumerWidget {
  const AppWatermark({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => StreamBuilder<String?>(
    stream: _companyLogoStream(ref),
    builder: (context, snapshot) {
      final logoPath = snapshot.data;
      final hasCompanyLogo = logoPath != null && File(logoPath).existsSync();
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: child),
          IgnorePointer(
            child: Center(
              child: Opacity(
                opacity: .045,
                child: FractionallySizedBox(
                  widthFactor: .42,
                  heightFactor: .42,
                  child: hasCompanyLogo
                      ? Image.file(File(logoPath), fit: BoxFit.contain)
                      : Image.asset(
                          'assets/branding/systock_logo_transparent.png',
                          fit: BoxFit.contain,
                        ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

Stream<String?> _companyLogoStream(WidgetRef ref) {
  final database = ref.watch(databaseProvider);
  return database
      .customSelect(
        'SELECT logo_path FROM companies LIMIT 1',
        readsFrom: {database.companies},
      )
      .watchSingleOrNull()
      .map((row) => row?.readNullable<String>('logo_path'));
}
