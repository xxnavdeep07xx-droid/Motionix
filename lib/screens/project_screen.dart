import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../core/bindings.dart';
import '../core/media_service.dart';
import '../models.dart';
import '../widgets/brand.dart';
import '../widgets/filmstrip.dart';

/// Phase 1 pipeline screen:
/// import → probe → C++ proxy plan → hardware proxy transcode →
/// scrub bench (filmstrip + trim + timecode from C++) → full-quality export.
class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key, required this.pickedFile, required this.lowRam});

  final XFile pickedFile;
  final bool lowRam;

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

enum _Stage { probing, planning, proxying, ready, exporting, done, failed }

class _ProjectScreenState extends State<ProjectScreen>
    with SingleTickerProviderStateMixin {
  _Stage _stage = _Stage.probing;
  String? _error;
  int _percent = 0;

  late String _sourcePath;
  String _proxyPath = '';
  MediaInfo? _info;
  ProxyPlan? _plan;
  String _projectJson = '';
  String _projectFile = '';
  int _mediaId = 1;
  int _sourceBytes = 0;

  VideoPlayerController? _controller;
  List<String> _thumbs = const [];
  RangeValues _trim = const RangeValues(0, 1);
  bool _trimDirty = false;

  late final Ticker _ticker;
  int _uiFrames = 0;
  int _uiFps = 0;
  int _scrubEvents = 0;
  int _scrubPerSec = 0;
  Timer? _meterTimer;
  Timer? _seekDebounce;
  Timer? _trimDebounce;
  StreamSubscription<ProgressEvent>? _progressSub;

  String? _exportPath;
  int _exportBytes = 0;

  MediaInfo get _media => _info!;
  ProxyPlan get _proxyPlan => _plan!;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _uiFrames++);
    _meterTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _uiFps = _uiFrames;
        _scrubPerSec = _scrubEvents;
        _uiFrames = 0;
        _scrubEvents = 0;
      });
    });
    _startPipeline();
  }

  @override
  void dispose() {
    _meterTimer?.cancel();
    _seekDebounce?.cancel();
    _trimDebounce?.cancel();
    _progressSub?.cancel();
    _ticker.dispose();
    _controller?.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- pipeline

  Future<void> _startPipeline() async {
    try {
      // 1. Copy the picked file into our persistent media inbox.
      final docs = await getApplicationDocumentsDirectory();
      final inbox = Directory('${docs.path}/media');
      await inbox.create(recursive: true);
      final dest =
          '${inbox.path}/${DateTime.now().millisecondsSinceEpoch}_${widget.pickedFile.name}';
      _sourcePath = (await File(widget.pickedFile.path).copy(dest)).path;
      _sourceBytes = await File(_sourcePath).length();

      // 2. Probe with MediaMetadataRetriever.
      final info = await MediaService.instance.probe(_sourcePath);
      if (!mounted) return;
      setState(() => _info = info);

      // 3. Ask the C++ core for a proxy plan.
      final core = CoreBindings.instance;
      final plan = core.probePlan(
        width: info.width,
        height: info.height,
        fpsNum: info.fpsNum,
        fpsDen: info.fpsDen,
        durationUs: info.durationUs,
        lowRam: widget.lowRam,
      );
      if (!plan.ok) throw plan.error ?? 'proxy planner failed';
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _stage = _Stage.planning;
      });

      // 4. Create the project envelope and register the media item.
      final baseName = widget.pickedFile.name;
      _projectJson = core.projectNew(baseName);
      _projectJson = core.projectAddMedia(_projectJson, {
        'name': baseName,
        'sourcePath': _sourcePath,
        'width': info.width,
        'height': info.height,
        'fpsNum': info.fpsNum,
        'fpsDen': info.fpsDen,
        'durationUs': info.durationUs,
        'nowMs': DateTime.now().millisecondsSinceEpoch,
      });
      final decoded = jsonDecode(_projectJson) as Map<String, dynamic>;
      final mediaList = decoded['media'] as List<dynamic>;
      _mediaId = (mediaList.first as Map<String, dynamic>)['id'] as int;
      await _saveProjectFile();

      // 5. Build the proxy (or edit directly when the source is light).
      if (plan.passthrough) {
        _proxyPath = _sourcePath;
        await _onProxyReady();
        return;
      }
      final proxies = Directory('${docs.path}/proxies');
      await proxies.create(recursive: true);
      _proxyPath =
          '${proxies.path}/p${DateTime.now().millisecondsSinceEpoch}.mp4';
      if (!mounted) return;
      setState(() => _stage = _Stage.proxying);
      _progressSub = MediaService.instance
          .progress()
          .where((e) => e.stage == 'proxy')
          .listen(_onProxyProgress,
              onError: (Object e) => _fail(e.toString()));
      await MediaService.instance.buildProxy(
        src: _sourcePath,
        out: _proxyPath,
        height: plan.targetHeight,
        videoBitrate: plan.videoBitrate,
        audioBitrate: plan.audioBitrate,
      );
    } catch (e) {
      _fail(e.toString());
    }
  }

  void _onProxyProgress(ProgressEvent e) {
    if (!mounted) return;
    if (e.error != null) {
      _fail(e.error!);
      return;
    }
    setState(() => _percent = e.percent ?? _percent);
    if (e.done) _onProxyReady();
  }

  Future<void> _onProxyReady() async {
    try {
      if (!mounted) return;
      _progressSub?.cancel();
      setState(() => _stage = _Stage.ready);
      _ticker.start();

      final c = VideoPlayerController.file(File(_proxyPath));
      await c.initialize();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => _controller = c);
      c.addListener(() {
        if (mounted) setState(() {});
      });
      await c.setLooping(true);
      await c.play();

      _trim = RangeValues(0, c.value.duration.inMicroseconds.toDouble());
      setState(() {});

      // Filmstrip thumbnails from the proxy — sync frames, so it is fast.
      final thumbs = await MediaService.instance
          .thumbnails(_proxyPath, count: 12, height: 120);
      if (mounted) setState(() => _thumbs = thumbs);
    } catch (e) {
      _fail(e.toString());
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.failed;
      _error = message;
    });
  }

  Future<void> _saveProjectFile() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/projects');
    await dir.create(recursive: true);
    if (_projectFile.isEmpty) {
      _projectFile =
          '${dir.path}/motionix_${DateTime.now().millisecondsSinceEpoch}.json';
    }
    await File(_projectFile).writeAsString(_projectJson);
  }

  // ------------------------------------------------------------- controls

  void _onScrub(double us) {
    _scrubEvents++;
    _seekDebounce?.cancel();
    _seekDebounce = Timer(const Duration(milliseconds: 90), () {
      _controller?.seekTo(Duration(microseconds: us.toInt()));
    });
  }

  void _onTrimChanged(RangeValues v) {
    // Enforce a 0.2 s minimum span (no minDistance param on RangeSlider).
    const minSpan = 200000.0;
    if (v.end - v.start < minSpan) {
      if (v.start != _trim.start) {
        v = RangeValues(v.end - minSpan, v.end);
      } else {
        v = RangeValues(v.start, v.start + minSpan);
      }
      v = RangeValues(v.start.clamp(0, 1e9), v.end.clamp(0, 1e9));
    }
    setState(() {
      _trim = v;
      _trimDirty = true;
    });
    _trimDebounce?.cancel();
    _trimDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        _projectJson = CoreBindings.instance.projectSetTrim(
            _projectJson, _mediaId, v.start.toInt(), v.end.toInt());
        await _saveProjectFile();
        if (mounted) setState(() => _trimDirty = false);
      } catch (_) {/* keep editing; save retries next change */}
    });
  }

  Future<void> _export() async {
    if (_stage != _Stage.ready) return;
    final docs = await getExternalStorageDirectory();
    final outDir = docs ?? await getApplicationDocumentsDirectory();
    final out =
        '${outDir.path}/Motionix_${DateTime.now().millisecondsSinceEpoch}.mp4';
    setState(() {
      _stage = _Stage.exporting;
      _percent = 0;
    });
    _progressSub?.cancel();
    _progressSub = MediaService.instance
        .progress()
        .where((e) => e.stage == 'export')
        .listen((e) {
      if (!mounted) return;
      if (e.error != null) {
        _fail(e.error!);
        return;
      }
      setState(() => _percent = e.percent ?? _percent);
      if (e.done && e.path != null) {
        setState(() => _percent = 100);
        _onExportDone(e.path!);
      }
    });
    try {
      final height = _media.height < 1080 ? _media.height : 1080;
      await MediaService.instance.exportTrim(
        src: _sourcePath,
        out: out,
        startUs: _trim.start.toInt(),
        endUs: _trim.end.toInt(),
        height: height,
      );
    } catch (e) {
      _fail(e.toString());
    }
  }

  Future<void> _onExportDone(String path) async {
    _progressSub?.cancel();
    final bytes = await File(path).length();
    if (!mounted) return;
    setState(() {
      _exportPath = path;
      _exportBytes = bytes;
      _stage = _Stage.done;
    });
  }

  // ----------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Brand.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.pickedFile.name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        actions: [
          if (_stage == _Stage.ready)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                visualDensity: VisualDensity.compact,
                backgroundColor: _trimDirty ? Brand.surface : Brand.surfaceHi,
                side: const BorderSide(color: Brand.border),
                label: Text(
                  _trimDirty ? 'saving…' : 'project saved',
                  style: const TextStyle(fontSize: 10, color: Brand.subtext),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_stage) {
      case _Stage.probing:
      case _Stage.planning:
      case _Stage.proxying:
        return _buildWorking();
      case _Stage.ready:
        return _buildEditor();
      case _Stage.exporting:
        return _buildExporting();
      case _Stage.done:
        return _buildDone();
      case _Stage.failed:
        return _buildFailed();
    }
  }

  Widget _buildWorking() {
    final label = switch (_stage) {
      _Stage.probing => 'Reading the clip…',
      _Stage.planning => 'Planning proxies (C++ core)…',
      _ => 'Building ${_plan?.ladder ?? ''} proxy — hardware encoder…',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_stage == _Stage.proxying)
              SizedBox(
                width: 220,
                child: LinearProgressIndicator(
                  value: (_percent / 100).clamp(0.0, 1.0),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              )
            else
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            const SizedBox(height: 20),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Brand.text, fontSize: 14)),
            if (_stage == _Stage.proxying) ...[
              const SizedBox(height: 6),
              Text('$_percent%',
                  style: const TextStyle(color: Brand.subtext, fontSize: 12)),
            ],
            if (_plan != null && _stage == _Stage.proxying) ...[
              const SizedBox(height: 10),
              Text(
                '${_plan!.reason} · ≈${_plan!.estimatedMb} MB · ${_plan!.bitrateLabel}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Brand.subtext, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEditor() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 3));
    }
    final durUs = c.value.duration.inMicroseconds;
    final posUs = c.value.position.inMicroseconds;
    final core = CoreBindings.instance;
    final fpsNum = _media.fpsNum;
    final fpsDen = _media.fpsDen;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: c.value.aspectRatio,
            child: VideoPlayer(c),
          ),
        ),
        const SizedBox(height: 10),

        Row(
          children: [
            IconButton.filled(
              style: IconButton.styleFrom(
                  backgroundColor: Brand.surfaceHi,
                  foregroundColor: Brand.text),
              onPressed: () {
                setState(() {
                  c.value.isPlaying ? c.pause() : c.play();
                });
              },
              icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${core.timecode(posUs, fpsNum: fpsNum, fpsDen: fpsDen)}'
                    '  /  ${core.timecode(durUs, fpsNum: fpsNum, fpsDen: fpsDen)}',
                    style: Brand.mono.copyWith(color: Brand.text, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'timecode from the C++ core · ${_media.fpsLabel}',
                    style: const TextStyle(color: Brand.subtext, fontSize: 10),
                  ),
                ],
              ),
            ),
            Text('$_uiFps fps UI',
                style: Brand.mono.copyWith(color: Brand.magenta, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),

        Slider(
          value: posUs.clamp(0, durUs).toDouble(),
          max: durUs.toDouble(),
          activeColor: Brand.azure,
          onChanged: _onScrub,
          onChangeEnd: (v) => c.seekTo(Duration(microseconds: v.toInt())),
        ),

        if (_thumbs.isNotEmpty)
          Filmstrip(
            thumbs: _thumbs,
            playhead: durUs == 0 ? 0.0 : posUs / durUs,
          ),
        const SizedBox(height: 18),

        _SectionTitle(
            title: 'TRIM RANGE',
            trailing: Text(
              '${core.timecode(_trim.start.toInt(), fpsNum: fpsNum, fpsDen: fpsDen)} → '
              '${core.timecode(_trim.end.toInt(), fpsNum: fpsNum, fpsDen: fpsDen)}',
              style: Brand.mono.copyWith(color: Brand.azure, fontSize: 11),
            )),
        RangeSlider(
          values: _trim,
          max: durUs.toDouble(),
          activeColor: Brand.violet,
          onChanged: _onTrimChanged,
        ),
        const SizedBox(height: 6),

        _SectionTitle(title: 'ENGINE BENCH'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatChip(label: 'Source', value: _media.resolutionLabel),
            StatChip(label: 'Rate', value: _media.fpsLabel),
            StatChip(label: 'File', value: prettyMb(_sourceBytes)),
            StatChip(
                label: 'Proxy',
                value: _proxyPlan.passthrough
                    ? 'direct'
                    : '${_proxyPlan.targetWidth}x${_proxyPlan.targetHeight}'),
            if (!_proxyPlan.passthrough)
              StatChip(
                  label: 'Proxy file',
                  value: prettyMb(File(_proxyPath).lengthSync())),
            StatChip(label: 'Scrub', value: '$_scrubPerSec ev/s'),
            StatChip(
                label: 'Device RAM',
                value: widget.lowRam ? 'sim 4 GB' : 'native'),
          ],
        ),
        const SizedBox(height: 24),

        _GradientButton(
          label:
              'Export full quality (${((_trim.end - _trim.start) / 1e6).toStringAsFixed(1)} s)',
          icon: Icons.movie_creation_outlined,
          onPressed: _export,
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            'Export renders from the ORIGINAL file — the proxy is only an editing aid.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Brand.subtext, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildExporting() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 220,
              child: LinearProgressIndicator(
                value: (_percent / 100).clamp(0.0, 1.0),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Rendering your movie — hardware encoder…',
                style: TextStyle(fontSize: 14)),
            const SizedBox(height: 6),
            Text('$_percent%',
                style: const TextStyle(color: Brand.subtext, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildDone() {
    final sizeLabel = _exportBytes >= 1000000
        ? '${(_exportBytes / 1000000).toStringAsFixed(1)} MB'
        : '${(_exportBytes / 1000).round()} KB';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                  gradient: Brand.brandGradient, shape: BoxShape.circle),
              child: const Icon(Icons.check, size: 36, color: Colors.white),
            ),
            const SizedBox(height: 18),
            const Text('Export complete',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Motionix · $sizeLabel',
                style: const TextStyle(color: Brand.subtext, fontSize: 12)),
            const SizedBox(height: 8),
            Text(
              _exportPath ?? '',
              textAlign: TextAlign.center,
              style: Brand.mono.copyWith(color: Brand.subtext, fontSize: 10),
            ),
            const SizedBox(height: 22),
            _GradientButton(
              label: 'Share',
              icon: Icons.share,
              onPressed: () async {
                if (_exportPath == null) return;
                await Share.shareXFiles([XFile(_exportPath!)],
                    text: 'Made with Motionix');
              },
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to project'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailed() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44, color: Brand.magenta),
            const SizedBox(height: 14),
            const Text('Something tripped the engine',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_error ?? 'unknown error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Brand.subtext, fontSize: 12)),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Brand.subtext,
                  letterSpacing: 1)),
          ?trailing,
        ],
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton(
      {required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: Brand.brandGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}
