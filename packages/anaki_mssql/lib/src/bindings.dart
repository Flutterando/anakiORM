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

/// Holds all resolved FFI function pointers for the native library.
class AnakiMssqlBindings {
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

  AnakiMssqlBindings._({
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

  /// Loads bindings from a [DynamicLibrary].
  factory AnakiMssqlBindings.fromLibrary(DynamicLibrary lib) {
    return AnakiMssqlBindings._(
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
