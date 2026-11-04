import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';

import '../core/bindings.dart';
import '../core/media_service.dart';
import '../models.dart';
import '../widgets/brand.dart';
import 'project_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DeviceInfo? _device;
  bool _lowRamMode = false;
  bool _picking = false;
  late final String _coreVersion;

  @override
  void initState() {
    super.initState();
    _coreVersion = CoreBindings.instance.version;
    MediaService.instance.deviceInfo().then((d) {
      if (mounted) setState(() => _device = d);
    }).catchError((_) {
      // Host tests / platforms without the media bridge — degrade quietly.
    });
  }

  Future<void> _newProject() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked =
          await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (picked == null) return;
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProjectScreen(pickedFile: picked, lowRam: _lowRamMode),
      ));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          children: [
            const SizedBox(height: 8),
            Center(
              child: SvgPicture.asset(
                'assets/branding/motionix_mark.svg',
                width: 108,
                height: 108,
              ),
            ),
            const SizedBox(height: 20),
            const Center(
              child: GradientText(
                'Motionix',
                style: TextStyle(
                    fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: 1),
              ),
            ),
            const SizedBox(height: 6),
            const Center(
              child: Text(
                'The pocket studio — pro editing that fits in 4 GB',
                style: TextStyle(color: Brand.subtext, fontSize: 13),
              ),
            ),
            const SizedBox(height: 36),
            _GradientButton(
              label: _picking ? 'Opening gallery…' : 'New project',
              icon: Icons.add,
              onPressed: _newProject,
            ),
            const SizedBox(height: 28),

            // How the magic works — three honest steps.
            _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('How Phase 1 works',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 12),
                  _step('1', 'Import any clip — even 4K/60 from your camera'),
                  _step('2',
                      'The engine builds a smart proxy so scrubbing stays buttery'),
                  _step('3',
                      'Trim on the bench, then export full quality from the ORIGINAL file'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Low-RAM simulation toggle.
            _Panel(
              child: SwitchListTile(
                value: _lowRamMode,
                onChanged: (v) => setState(() => _lowRamMode = v),
                contentPadding: EdgeInsets.zero,
                activeThumbColor: Brand.violet,
                title: const Text('Simulate 4 GB device',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    'Plans 540p proxies with leaner bitrates — test the promise on a flagship',
                    style: TextStyle(fontSize: 12, color: Brand.subtext)),
              ),
            ),
            const SizedBox(height: 16),

            // Device card.
            _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('This device',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      StatChip(
                          label: 'Model',
                          value: _device?.model ?? '…'),
                      StatChip(
                          label: 'Android',
                          value: _device == null ? '…' : 'API ${_device!.androidSdk}'),
                      StatChip(
                          label: 'RAM',
                          value: _device == null
                              ? '…'
                              : '${_device!.totalRamMb} MB'),
                      StatChip(
                          label: 'App heap',
                          value: _device == null
                              ? '…'
                              : '${_device!.memoryClass} MB'),
                      StatChip(
                          label: 'ABI', value: _device?.abi ?? '…'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Center(
              child: Column(
                children: [
                  Text(_coreVersion,
                      style:
                          const TextStyle(color: Brand.subtext, fontSize: 11)),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Brand.border),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text('Phase 1 · Engine proof · 100% free',
                        style: TextStyle(color: Brand.subtext, fontSize: 10)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(String n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                gradient: Brand.brandGradient, shape: BoxShape.circle),
            child: Text(n,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style:
                    const TextStyle(color: Brand.subtext, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Material (not Container) so ListTile/SwitchListTile ink splashes paint
    // on this surface instead of being hidden by a DecoratedBox.
    return Material(
      color: Brand.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Brand.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
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
        boxShadow: [
          BoxShadow(
            color: Brand.violet.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}
