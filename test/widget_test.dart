import 'package:flutter_test/flutter_test.dart';

import 'package:motionix/core/bindings.dart';
import 'package:motionix/main.dart';

void main() {
  testWidgets('Motionix boots to the home screen', (tester) async {
    await tester.pumpWidget(const MotionixApp());
    expect(find.text('Motionix'), findsWidgets);
  });

  test('FFI bridge round-trips through the real C++ core', () {
    final core = CoreBindings.instance;
    expect(core.isAvailable, isTrue,
        reason: 'tests must run with the host core built (see CI workflow)');

    // Diagnostics + rational timecode computed in C++.
    expect(core.version, contains('motionix-core'));
    expect(core.timecode(0), '00:00:00:00');
    expect(core.timecode(3661500000, fpsNum: 30000, fpsDen: 1001),
        matches(RegExp(r'^\d{2}:\d{2}:\d{2}:\d{2}$')));

    // Proxy planner: a 4K/29.97 clip on a simulated 4 GB device must land on
    // the lean end of the ladder — this is the Phase 1 promise in one call.
    final plan = core.probePlan(
      width: 3840,
      height: 2160,
      fpsNum: 30000,
      fpsDen: 1001,
      durationUs: 60 * 1000 * 1000,
      lowRam: true,
    );
    expect(plan.ok, isTrue, reason: plan.error ?? 'planner refused input');
    expect(plan.passthrough, isFalse); // 4K never passes through untouched
    expect(plan.targetHeight, lessThanOrEqualTo(540));
    expect(plan.targetWidth, greaterThan(0));
    expect(plan.videoBitrate, greaterThan(0));
    expect(plan.audioBitrate, greaterThan(0));

    // Project model: create -> add media -> trim -> validate, all in C++.
    // (The core assigns media ids itself — the first clip is id 1.)
    var project = core.projectNew('FFI test project');
    project = core.projectAddMedia(project, {
      'name': 'clip.mp4',
      'sourcePath': '/tmp/clip.mp4',
      'durationUs': 10 * 1000 * 1000,
      'nowMs': 0,
    });
    project = core.projectSetTrim(project, 1, 1000000, 4000000);
    final report = core.projectValidate(project);
    expect(report['ok'], isTrue, reason: '${report['error']}');

    // And a deliberately bad trim must be rejected by the core.
    final broken = core.projectSetTrim(project, 0, 4000000, 1000000);
    expect(core.projectValidate(broken)['ok'], isFalse);
  });
}
