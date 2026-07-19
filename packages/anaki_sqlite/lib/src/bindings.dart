import 'dart:ffi';
import 'package:ffi/ffi.dart';

// ─── Native function typedefs ───

// C signatures
typedef AnakiOpenNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef AnakiCloseNative = Pointer<Utf8> Function();
typedef AnakiQueryNative = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef AnakiExecuteNative =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef AnakiExecuteBatchNative =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef AnakiBeginTransactionNative = Pointer<Utf8> Function();
typedef AnakiCommitNative = Pointer<Utf8> Function();
typedef AnakiRollbackNative = Pointer<Utf8> Function();
typedef AnakiPingNative = Pointer<Utf8> Function();
typedef AnakiFreeStringNative = Void Function(Pointer<Utf8>);

// Dart signatures
typedef AnakiOpenDart = Pointer<Utf8> Function(Pointer<Utf8>);
typedef AnakiCloseDart = Pointer<Utf8> Function();
typedef AnakiQueryDart = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef AnakiExecuteDart = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef AnakiExecuteBatchDart =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef AnakiBeginTransactionDart = Pointer<Utf8> Function();
typedef AnakiCommitDart = Pointer<Utf8> Function();
typedef AnakiRollbackDart = Pointer<Utf8> Function();
typedef AnakiPingDart = Pointer<Utf8> Function();
typedef AnakiFreeStringDart = void Function(Pointer<Utf8>);

// ─── Native-asset externs ───
//
// The asset id must match the CodeAsset registered by hook/build.dart
// (package + '<package>.dart'). The Dart runtime resolves these against the
// asset bundled by `dart build`/`flutter build` — including the macOS
// framework layout (Contents/Frameworks/<name>.framework/<name>), which the
// filesystem search below can never find.

const String _assetId = 'package:anaki_sqlite/anaki_sqlite.dart';

@Native<AnakiOpenNative>(symbol: 'anaki_open', assetId: _assetId)
external Pointer<Utf8> _anakiOpen(Pointer<Utf8> config);

@Native<AnakiCloseNative>(symbol: 'anaki_close', assetId: _assetId)
external Pointer<Utf8> _anakiClose();

@Native<AnakiQueryNative>(symbol: 'anaki_query', assetId: _assetId)
external Pointer<Utf8> _anakiQuery(Pointer<Utf8> sql, Pointer<Utf8> params);

@Native<AnakiExecuteNative>(symbol: 'anaki_execute', assetId: _assetId)
external Pointer<Utf8> _anakiExecute(Pointer<Utf8> sql, Pointer<Utf8> params);

@Native<AnakiExecuteBatchNative>(
  symbol: 'anaki_execute_batch',
  assetId: _assetId,
)
external Pointer<Utf8> _anakiExecuteBatch(
  Pointer<Utf8> sql,
  Pointer<Utf8> paramsList,
);

@Native<AnakiBeginTransactionNative>(
  symbol: 'anaki_begin_transaction',
  assetId: _assetId,
)
external Pointer<Utf8> _anakiBeginTransaction();

@Native<AnakiCommitNative>(symbol: 'anaki_commit', assetId: _assetId)
external Pointer<Utf8> _anakiCommit();

@Native<AnakiRollbackNative>(symbol: 'anaki_rollback', assetId: _assetId)
external Pointer<Utf8> _anakiRollback();

@Native<AnakiPingNative>(symbol: 'anaki_ping', assetId: _assetId)
external Pointer<Utf8> _anakiPing();

@Native<AnakiFreeStringNative>(symbol: 'anaki_free_string', assetId: _assetId)
external void _anakiFreeString(Pointer<Utf8> ptr);

/// Holds all resolved FFI function pointers for the native library.
class AnakiSqliteBindings {
  final AnakiOpenDart open;
  final AnakiCloseDart close;
  final AnakiQueryDart query;
  final AnakiExecuteDart execute;
  final AnakiExecuteBatchDart executeBatch;
  final AnakiBeginTransactionDart beginTransaction;
  final AnakiCommitDart commit;
  final AnakiRollbackDart rollback;
  final AnakiPingDart ping;
  final AnakiFreeStringDart freeString;

  AnakiSqliteBindings._({
    required this.open,
    required this.close,
    required this.query,
    required this.execute,
    required this.executeBatch,
    required this.beginTransaction,
    required this.commit,
    required this.rollback,
    required this.ping,
    required this.freeString,
  });

  /// Resolves bindings through the native-assets runtime (asset id).
  ///
  /// Throws if the asset was not bundled for this build — callers should
  /// fall back to [AnakiSqliteBindings.fromLibrary].
  factory AnakiSqliteBindings.fromNativeAssets() {
    return AnakiSqliteBindings._(
      open: Native.addressOf<NativeFunction<AnakiOpenNative>>(_anakiOpen)
          .asFunction(),
      close: Native.addressOf<NativeFunction<AnakiCloseNative>>(_anakiClose)
          .asFunction(),
      query: Native.addressOf<NativeFunction<AnakiQueryNative>>(_anakiQuery)
          .asFunction(),
      execute:
          Native.addressOf<NativeFunction<AnakiExecuteNative>>(_anakiExecute)
              .asFunction(),
      executeBatch: Native.addressOf<NativeFunction<AnakiExecuteBatchNative>>(
        _anakiExecuteBatch,
      ).asFunction(),
      beginTransaction:
          Native.addressOf<NativeFunction<AnakiBeginTransactionNative>>(
        _anakiBeginTransaction,
      ).asFunction(),
      commit: Native.addressOf<NativeFunction<AnakiCommitNative>>(_anakiCommit)
          .asFunction(),
      rollback:
          Native.addressOf<NativeFunction<AnakiRollbackNative>>(_anakiRollback)
              .asFunction(),
      ping: Native.addressOf<NativeFunction<AnakiPingNative>>(_anakiPing)
          .asFunction(),
      freeString: Native.addressOf<NativeFunction<AnakiFreeStringNative>>(
        _anakiFreeString,
      ).asFunction(),
    );
  }

  /// Loads bindings from a [DynamicLibrary].
  factory AnakiSqliteBindings.fromLibrary(DynamicLibrary lib) {
    return AnakiSqliteBindings._(
      open: lib.lookupFunction<AnakiOpenNative, AnakiOpenDart>('anaki_open'),
      close: lib.lookupFunction<AnakiCloseNative, AnakiCloseDart>(
        'anaki_close',
      ),
      query: lib.lookupFunction<AnakiQueryNative, AnakiQueryDart>(
        'anaki_query',
      ),
      execute: lib.lookupFunction<AnakiExecuteNative, AnakiExecuteDart>(
        'anaki_execute',
      ),
      executeBatch: lib
          .lookupFunction<AnakiExecuteBatchNative, AnakiExecuteBatchDart>(
            'anaki_execute_batch',
          ),
      beginTransaction: lib
          .lookupFunction<
            AnakiBeginTransactionNative,
            AnakiBeginTransactionDart
          >('anaki_begin_transaction'),
      commit: lib.lookupFunction<AnakiCommitNative, AnakiCommitDart>(
        'anaki_commit',
      ),
      rollback: lib.lookupFunction<AnakiRollbackNative, AnakiRollbackDart>(
        'anaki_rollback',
      ),
      ping: lib.lookupFunction<AnakiPingNative, AnakiPingDart>('anaki_ping'),
      freeString: lib
          .lookupFunction<AnakiFreeStringNative, AnakiFreeStringDart>(
            'anaki_free_string',
          ),
    );
  }
}
