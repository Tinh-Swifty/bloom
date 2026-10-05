import 'package:flutter/material.dart';

import '../services/pairing.dart';
import '../services/session_store.dart';

/// First screen: pick a name, then create a code or enter the other
/// person's code.
class PairScreen extends StatefulWidget {
  const PairScreen({super.key, required this.store, required this.onPaired});

  final SessionStore store;
  final VoidCallback onPaired;

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  late final _name = TextEditingController(text: widget.store.name);
  final _code = TextEditingController();
  String? _nameError;
  String? _codeError;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  String? _validName() {
    final name = _name.text.trim();
    setState(() => _nameError = name.isEmpty ? 'Hãy nhập tên của bạn' : null);
    return name.isEmpty ? null : name;
  }

  Future<void> _create() async {
    final name = _validName();
    if (name == null) return;
    await widget.store.savePairing(code: Pairing.generateCode(), name: name);
    widget.onPaired();
  }

  Future<void> _join() async {
    final name = _validName();
    final code = Pairing.normalize(_code.text);
    setState(() => _codeError = code == null ? 'Mã gồm 12 ký tự' : null);
    if (name == null || code == null) return;
    await widget.store.savePairing(code: code, name: name);
    widget.onPaired();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Image.asset(
                        'assets/logo/logo.png',
                        width: 120,
                        height: 120,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Bên Nhau',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Chia sẻ vị trí giữa hai người',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 20,
                    decoration: InputDecoration(
                      labelText: 'Tên của bạn',
                      border: const OutlineInputBorder(),
                      errorText: _nameError,
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.add_link),
                    label: const Text('Tạo mã kết nối mới'),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text('hoặc nhập mã của người ấy'),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                  ),
                  TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Mã kết nối',
                      hintText: 'XXXX-XXXX-XXXX',
                      border: const OutlineInputBorder(),
                      errorText: _codeError,
                    ),
                    onSubmitted: (_) => _join(),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _join,
                    icon: const Icon(Icons.login),
                    label: const Text('Kết nối'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
