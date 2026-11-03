import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Typed view over the media metadata probed on the Kotlin side.
@immutable
class MediaInfo {
  const MediaInfo({
    required this.width,
    required this.height,
    required this.rotation,
    required this.durationUs,
    required this.hasAudio,
    required this.fpsNum,
    required this.fpsDen,
    required this.frameCount,
  });

  factory MediaInfo.fromMap(Map<Object?, Object?> m) {
    int? i(Object? v) => (v as num?)?.toInt();
    return MediaInfo(
      width: i(m['width']) ?? 0,
      height: i(m['height']) ?? 0,
      rotation: i(m['rotation']) ?? 0,
      durationUs: i(m['durationUs']) ?? 0,
      hasAudio: m['hasAudio'] == true,
      fpsNum: i(m['fpsNum']) ?? 30,
      fpsDen: i(m['fpsDen']) ?? 1,
      frameCount: i(m['frameCount']) ?? -1,
    );
  }

  final int width;
  final int height;
  final int rotation;
  final int durationUs;
  final bool hasAudio;
  final int fpsNum;
  final int fpsDen;
  final int frameCount;

  double get fps => fpsDen == 0 ? 30.0 : fpsNum / fpsDen;
  String get fpsLabel {
    final f = fps;
    final nice = f.roundToDouble();
    return (nice - f).abs() < 0.02
        ? '${nice.toInt()} fps'
        : '${f.toStringAsFixed(2)} fps';
  }

  String get resolutionLabel => '${width}x$height';
}

/// The C++ proxy plan: how we make this clip buttery on this device.
@immutable
class ProxyPlan {
  const ProxyPlan({
    required this.ok,
    required this.targetHeight,
    required this.targetWidth,
    required this.passthrough,
    required this.videoBitrate,
    required this.audioBitrate,
    required this.ladder,
    required this.estimatedMb,
    required this.reason,
    this.error,
  });

  factory ProxyPlan.fromMap(Map<String, dynamic> m) => ProxyPlan(
        ok: m['ok'] == true,
        targetHeight: (m['targetHeight'] as num?)?.toInt() ?? 0,
        targetWidth: (m['targetWidth'] as num?)?.toInt() ?? 0,
        passthrough: m['passthrough'] == true,
        videoBitrate: (m['videoBitrate'] as num?)?.toInt() ?? 0,
        audioBitrate: (m['audioBitrate'] as num?)?.toInt() ?? 0,
        ladder: (m['ladder'] as String?) ?? '',
        estimatedMb: (m['estimatedMb'] as num?)?.toDouble() ?? 0,
        reason: (m['reason'] as String?) ?? '',
        error: m['error'] as String?,
      );

  final bool ok;
  final int targetHeight;
  final int targetWidth;
  final bool passthrough;
  final int videoBitrate;
  final int audioBitrate;
  final String ladder;
  final double estimatedMb;
  final String reason;
  final String? error;

  String get bitrateLabel => '${(videoBitrate / 1000000).toStringAsFixed(1)} Mb/s';
}

@immutable
class DeviceInfo {
  const DeviceInfo({
    required this.model,
    required this.androidSdk,
    required this.totalRamMb,
    required this.memoryClass,
    required this.isLowRamDevice,
    required this.abi,
  });

  factory DeviceInfo.fromMap(Map<Object?, Object?> m) {
    int? i(Object? v) => (v as num?)?.toInt();
    return DeviceInfo(
      model: m['model'] as String? ?? 'Android device',
      androidSdk: i(m['androidSdk']) ?? 0,
      totalRamMb: i(m['totalRamMb']) ?? 0,
      memoryClass: i(m['memoryClass']) ?? 0,
      isLowRamDevice: m['isLowRamDevice'] == true,
      abi: m['abi'] as String? ?? '',
    );
  }

  final String model;
  final int androidSdk;
  final int totalRamMb;
  final int memoryClass;
  final bool isLowRamDevice;
  final String abi;
}

@immutable
class ProgressEvent {
  const ProgressEvent({
    required this.stage,
    this.percent,
    this.done = false,
    this.path,
    this.error,
  });

  factory ProgressEvent.fromMap(Map<Object?, Object?> m) {
    int? i(Object? v) => (v as num?)?.toInt();
    return ProgressEvent(
      stage: m['stage'] as String? ?? '',
      percent: i(m['percent']),
      done: m['done'] == true,
      path: m['path'] as String?,
      error: m['error'] as String?,
    );
  }

  final String stage;
  final int? percent;
  final bool done;
  final String? path;
  final String? error;
}

/// Progress payload used by the export result card.
@immutable
class ExportResult {
  const ExportResult({required this.path, required this.sizeBytes});
  final String path;
  final int sizeBytes;

  String get sizeLabel {
    final mb = sizeBytes / 1000000.0;
    return mb >= 1 ? '${mb.toStringAsFixed(1)} MB' : '${(sizeBytes / 1000).round()} KB';
  }
}

String prettyMb(int bytes) {
  final mb = bytes / 1000000.0;
  return mb >= 1 ? '${mb.toStringAsFixed(1)} MB' : '${(bytes / 1000).round()} KB';
}

/// Convenience for reading maps that arrived from the platform side.
Map<Object?, Object?> asPlatformMap(Object? v) =>
    v == null ? const {} : Map<Object?, Object?>.from(v as Map);

Map<String, dynamic> parseJsonMap(String s) {
  final decoded = jsonDecode(s);
  return Map<String, dynamic>.from(decoded as Map);
}
