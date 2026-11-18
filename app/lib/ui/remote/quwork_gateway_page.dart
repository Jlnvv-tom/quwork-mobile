import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/quwork_gateway_state.dart';
import '../shell/page_frame.dart';
import 'pairing_page.dart' show pairingScannerProvider;

class QuWorkGatewayPage extends ConsumerStatefulWidget {
  const QuWorkGatewayPage({super.key});
  @override
  ConsumerState<QuWorkGatewayPage> createState() => _QuWorkGatewayPageState();
}

class _QuWorkGatewayPageState extends ConsumerState<QuWorkGatewayPage> {
  final _qr = TextEditingController();
  bool _scanning = false;
  @override
  void dispose() {
    _qr.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final uri = Uri.tryParse(_qr.text.trim());
    if (uri == null) {
      _show(context.l10n.quworkGatewayQrInvalid);
      return;
    }
    final ok = await ref.read(quWorkGatewayProvider.notifier).pair(uri);
    if (mounted && ok) _show(context.l10n.quworkGatewayConnected);
  }

  void _show(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final gateway = ref.watch(quWorkGatewayProvider);
    return AppPage.list(
      title: context.l10n.quworkGatewayTitle,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text(context.l10n.quworkGatewayIntro)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: TextField(
            controller: _qr,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(labelText: context.l10n.quworkGatewayQr),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _scanning = !_scanning),
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(_scanning ? context.l10n.commonClose : context.l10n.quworkGatewayScan),
          ),
        ),
        if (_scanning)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: 260,
              child: ref.watch(pairingScannerProvider)(context, (value) {
                _qr.text = value;
                setState(() => _scanning = false);
                _pair();
              }),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledButton(
            onPressed: gateway.phase == QuWorkGatewayPhase.pairing ? null : _pair,
            child: Text(context.l10n.quworkGatewayPair),
          ),
        ),
        if (gateway.credential != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('${context.l10n.quworkGatewayDevice}: ${gateway.credential!.deviceId}'),
          ),
        if (gateway.error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('${context.l10n.quworkGatewayFailed}: ${gateway.error}'),
          ),
        if (gateway.connected)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton(
              onPressed: () => ref.read(quWorkGatewayProvider.notifier).signOut(),
              child: Text(context.l10n.quworkLoginSignOut),
            ),
          ),
      ],
    );
  }
}
