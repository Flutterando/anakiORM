import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final packageName = input.packageName;
    final os = input.config.code.targetOS;
    final arch = input.config.code.targetArchitecture;

    // Map OS to string
    final osStr = switch (os) {
      OS.macOS => 'darwin',
      OS.linux => 'linux',
      OS.windows => 'windows',
      _ => throw UnsupportedError('Unsupported OS: $os'),
    };

    // Map architecture to string
    final archStr = switch (arch) {
      Architecture.arm64 => 'arm64',
      Architecture.x64 => 'x64',
      _ => throw UnsupportedError('Unsupported architecture: $arch'),
    };

    // Map OS to file extension
    final ext = switch (os) {
      OS.macOS => 'dylib',
      OS.linux => 'so',
      OS.windows => 'dll',
      _ => 'so',
    };

    // Build native library filename
    final libName = os == OS.windows
        ? 'anaki_redis-$osStr-$archStr.$ext'
        : 'libanaki_redis-$osStr-$archStr.$ext';

    final nativeLibPath = input.packageRoot.resolve('native_libs/$libName');
    final file = File.fromUri(nativeLibPath);

    if (!file.existsSync()) {
      throw FileSystemException(
        'Native library not found: $libName. '
        'Run scripts/build_native.sh redis to build it.',
        nativeLibPath.toFilePath(),
      );
    }

    // Copy to output directory
    final outputFileName = os == OS.windows
        ? 'anaki_redis.dll'
        : 'libanaki_redis.$ext';
    // outputDirectory (NOT outputDirectoryShared): it is unique per build
    // config, so each architecture of a universal macOS build gets its own
    // copy. The shared directory made both arm64/x64 slices point to the
    // same file (last write wins), breaking lipo with duplicate archs.
    final outputFile = File.fromUri(
      input.outputDirectory.resolve(outputFileName),
    );
    await file.copy(outputFile.path);

    // Register the code asset
    output.assets.code.add(
      CodeAsset(
        package: packageName,
        name: '$packageName.dart',
        file: outputFile.uri,
        linkMode: DynamicLoadingBundled(),
      ),
    );
  });
}
