import 'dart:async';

import 'package:flutter/services.dart';

import '../models.dart';

/// Platform media service: probe, thumbnails, proxy transcode, export.
/// All heavy work happens in Media3 on the Kotlin side; hardware codecs
/// do the pixel pushing so the app never buffers raw frames in Dart.
class MediaService {
  MediaService._();

  static final MediaService instance = MediaService._();

  static const _methods = MethodChannel('motionix/media');
  static const _progress = EventChannel('motionix/progress');

  Stream<ProgressEvent>? _progressStream;

  /// Broadcast stream of proxy/export progress.
  Stream<ProgressEvent> progress() {
    return _progressStream ??= _progress
        .receiveBroadcastStream()
        .map(asProgressEvent)
        .asBroadcastStream();
  }

  static ProgressEvent asProgressEvent(Object? event) =>
      ProgressEvent.fromMap(asPlatformMap(event));

  Future<DeviceInfo> deviceInfo() async {
    final m = await _methods.invokeMethod('deviceInfo');
    return DeviceInfo.fromMap(asPlatformMap(m));
  }

  Future<MediaInfo> probe(String path) async {
    final m = await _methods.invokeMethod('probe', {'path': path});
    return MediaInfo.fromMap(asPlatformMap(m));
  }

  Future<List<String>> thumbnails(String path,
      {int count = 12, int height = 128}) async {
    final list = await _methods.invokeMethod(
        'thumbnails', {'path': path, 'count': count, 'height': height});
    if (list == null) return const [];
    return List<String>.from(list as List);
  }

  Future<void> buildProxy({
    required String src,
    required String out,
    required int height,
    required int videoBitrate,
    required int audioBitrate,
  }) async {
    await _methods.invokeMethod('buildProxy', {
      'src': src,
      'out': out,
      'height': height,
      'videoBitrate': videoBitrate,
      'audioBitrate': audioBitrate,
    });
  }

  Future<void> exportTrim({
    required String src,
    required String out,
    required int startUs,
    required int endUs,
    required int height,
  }) async {
    await _methods.invokeMethod('exportTrim', {
      'src': src,
      'out': out,
      'startUs': startUs,
      'endUs': endUs,
      'height': height,
    });
  }
}
