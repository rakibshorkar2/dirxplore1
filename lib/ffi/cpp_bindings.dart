import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'dart:io' show Platform;
import 'dart:typed_data';

// FFI Signatures for C++ Native I/O
typedef WriteChunkC = ffi.Int32 Function(ffi.Pointer<Utf8> filePath, ffi.Pointer<ffi.Uint8> data, ffi.Int32 length, ffi.Int64 offset);
typedef WriteChunkDart = int Function(ffi.Pointer<Utf8> filePath, ffi.Pointer<ffi.Uint8> data, int length, int offset);

class CppNativeIO {
  static final CppNativeIO _instance = CppNativeIO._internal();
  factory CppNativeIO() => _instance;

  late ffi.DynamicLibrary _lib;
  late WriteChunkDart _writeChunkFunc;

  CppNativeIO._internal() {
    _loadLibrary();
  }

  void _loadLibrary() {
    if (Platform.isAndroid) {
      _lib = ffi.DynamicLibrary.open('libnative_io.so');
    } else if (Platform.isLinux) {
      _lib = ffi.DynamicLibrary.open('libnative_io.so'); // Assuming built for Linux testing
    } else {
      throw UnsupportedError('C++ Native IO currently only built for Android/Linux.');
    }

    _writeChunkFunc = _lib.lookupFunction<WriteChunkC, WriteChunkDart>('WriteChunk');
  }

  /// Writes a chunk to a file via native C++ code to bypass Dart GC overhead
  bool writeChunk(String targetPath, Uint8List data, int offset) {
    if (data.isEmpty) return true;

    final targetPathPtr = targetPath.toNativeUtf8();
    
    // Allocate native memory and copy
    final ffi.Pointer<ffi.Uint8> dataPtr = malloc.allocate<ffi.Uint8>(data.length);
    final nativeList = dataPtr.asTypedList(data.length);
    nativeList.setAll(0, data);

    try {
      final result = _writeChunkFunc(targetPathPtr, dataPtr, data.length, offset);
      return result == 1; // 1 means success
    } finally {
      // Always free native memory
      malloc.free(targetPathPtr);
      malloc.free(dataPtr);
    }
  }
}
