import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../models.dart';

// ---------------------------------------------------------------------
// C signatures (top-level typedefs, dart:ffi style)
// ---------------------------------------------------------------------

typedef _VersionNative = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();

typedef _TimecodeNative = Pointer<Utf8> Function(Int64, Int64, Int64);
typedef _TimecodeDart = Pointer<Utf8> Function(int, int, int);

typedef _PlanNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _PlanDart = Pointer<Utf8> Function(Pointer<Utf8>);

typedef _ProjectNewNative = Pointer<Utf8> Function(Pointer<Utf8>, Int64);
typedef _ProjectNewDart = Pointer<Utf8> Function(Pointer<Utf8>, int);

typedef _AddMediaNative = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _AddMediaDart = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);

typedef _SetTrimNative = Pointer<Utf8> Function(
    Pointer<Utf8>, Int64, Int64, Int64);
typedef _SetTrimDart = Pointer<Utf8> Function(Pointer<Utf8>, int, int, int);

typedef _ValidateNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _ValidateDart = Pointer<Utf8> Function(Pointer<Utf8>);

typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);

/// dart:ffi bindings to libmotionix_core.so — the C++ engine core.
///
/// Phase 1 routes the rational math through real native code so the FFI
/// bridge, the memory discipline and the ABI are proven from day one.
class CoreBindings {
  CoreBindings._() : _lib = _openCore();

  static DynamicLibrary? _openCore() {
    try {
      return DynamicLibrary.open('libmotionix_core.so');
    } catch (_) {
      // Host builds (flutter test / desktop) have no packaged core.
      return null;
    }
  }

  static final CoreBindings instance = CoreBindings._();

  final DynamicLibrary? _lib;

  /// True when the native core is loaded (always true on Android).
  bool get isAvailable => _lib != null;

  late final _FreeDart _free = _lib!
      .lookupFunction<_FreeNative, _FreeDart>('mx_free_string');

  Pointer<Utf8> _toNative(String s) {
    final units = utf8.encode(s);
    final ptr = malloc<Uint8>(units.length + 1);
    final view = ptr.asTypedList(units.length + 1);
    view.setAll(0, units);
    view[units.length] = 0;
    return ptr.cast();
  }

  String _take(Pointer<Utf8> p) {
    final s = p.toDartString();
    _free(p);
    return s;
  }

  /// Core version string (static buffer — no free needed).
  String get version {
    if (_lib == null) return 'host build (no core)';
    final f = _lib.lookupFunction<_VersionNative, _VersionDart>('mx_version');
    return f().toDartString();
  }

  /// HH:MM:SS:FF at the given rational rate, computed in C++.
  String timecode(int us, {int fpsNum = 30, int fpsDen = 1}) {
    final f = _lib!
        .lookupFunction<_TimecodeNative, _TimecodeDart>('mx_timecode');
    return f(us, fpsNum, fpsDen).toDartString(); // static buffer
  }

  ProxyPlan probePlan({
    required int width,
    required int height,
    required int fpsNum,
    required int fpsDen,
    required int durationUs,
    required bool lowRam,
  }) {
    final f = _lib!.lookupFunction<_PlanNative, _PlanDart>('mx_probe_plan');
    final src = jsonEncode({
      'width': width,
      'height': height,
      'fpsNum': fpsNum,
      'fpsDen': fpsDen,
      'durationUs': durationUs,
      'lowRam': lowRam,
    });
    final out = _take(f(_toNative(src)));
    return ProxyPlan.fromMap(parseJsonMap(out));
  }

  String projectNew(String name) {
    final f = _lib!
        .lookupFunction<_ProjectNewNative, _ProjectNewDart>('mx_project_new');
    final now = DateTime.now().millisecondsSinceEpoch;
    return _take(f(_toNative(name), now));
  }

  String projectAddMedia(String projectJson, Map<String, dynamic> media) {
    final f = _lib!
        .lookupFunction<_AddMediaNative, _AddMediaDart>('mx_project_add_media');
    return _take(f(_toNative(projectJson), _toNative(jsonEncode(media))));
  }

  String projectSetTrim(String projectJson, int mediaId, int inUs, int outUs) {
    final f = _lib!
        .lookupFunction<_SetTrimNative, _SetTrimDart>('mx_project_set_trim');
    return _take(f(_toNative(projectJson), mediaId, inUs, outUs));
  }

  Map<String, dynamic> projectValidate(String projectJson) {
    final f = _lib!
        .lookupFunction<_ValidateNative, _ValidateDart>('mx_project_validate');
    return parseJsonMap(_take(f(_toNative(projectJson))));
  }
}
