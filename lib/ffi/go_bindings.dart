import 'dart:ffi' as ffi;
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'dart:io' show Platform;
import 'dart:convert';
import '../models/directory_item.dart';

// FFI Signatures
typedef DeepCrawlC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> targetUrl, ffi.Pointer<Utf8> proxyUri);
typedef DeepCrawlDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> targetUrl, ffi.Pointer<Utf8> proxyUri);

typedef FreeCStringC = ffi.Void Function(ffi.Pointer<Utf8> ptr);
typedef FreeCStringDart = void Function(ffi.Pointer<Utf8> ptr);

class GoCrawler {
  static final GoCrawler _instance = GoCrawler._internal();
  factory GoCrawler() => _instance;

  late ffi.DynamicLibrary _lib;
  late DeepCrawlDart _deepCrawlFunc;
  late FreeCStringDart _freeCStringFunc;

  GoCrawler._internal() {
    _loadLibrary();
  }

  void _loadLibrary() {
    if (Platform.isAndroid) {
      _lib = ffi.DynamicLibrary.open('libcrawler.so');
    } else if (Platform.isLinux) {
      _lib = ffi.DynamicLibrary.open('libcrawler.so'); // Assuming built for Linux testing
    } else {
      throw UnsupportedError('Go crawler currently only built for Android/Linux.');
    }

    _deepCrawlFunc = _lib.lookupFunction<DeepCrawlC, DeepCrawlDart>('DeepCrawl');
    _freeCStringFunc = _lib.lookupFunction<FreeCStringC, FreeCStringDart>('FreeCString');
  }

  /// Executes a Deep Crawl natively in Go logic
  /// Avoids Dart garbage collector freezing the UI thread for massive DOM trees
  List<DirectoryItem> deepCrawl(String targetUrl, {String proxyUri = ""}) {
    final targetUrlPtr = targetUrl.toNativeUtf8();
    final proxyUriPtr = proxyUri.toNativeUtf8();

    // Call Go shared library
    final resultPtr = _deepCrawlFunc(targetUrlPtr, proxyUriPtr);
    
    // Convert back from C string and Free
    final jsonResult = resultPtr.toDartString();
    _freeCStringFunc(resultPtr);
    
    // Free input strings
    malloc.free(targetUrlPtr);
    malloc.free(proxyUriPtr);

    // Parse JSON back to DirectoryItem list
    if (jsonResult.startsWith('{"error"')) {
       final errorMap = jsonDecode(jsonResult);
       throw Exception("Native Crawler Error: ${errorMap['error']}");
    }

    final List<dynamic> jsonList = jsonDecode(jsonResult);
    return jsonList.map((item) => DirectoryItem(
      name: item['name'],
      url: item['url'],
      type: item['type'] == 'directory' ? DirectoryItemType.directory : DirectoryItem.typeFromExtension(item['name']), // Simplified mapping
      size: item['size'],
    )).toList();
  }
}
