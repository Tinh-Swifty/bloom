import 'package:flutter/material.dart';

import 'screens/map_screen.dart';
import 'screens/pair_screen.dart';
import 'services/session_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await SessionStore.load();
  runApp(BenNhauApp(store: store));
}

class BenNhauApp extends StatefulWidget {
  const BenNhauApp({super.key, required this.store});

  final SessionStore store;

  @override
  State<BenNhauApp> createState() => _BenNhauAppState();
}

class _BenNhauAppState extends State<BenNhauApp> {
  @override
  Widget build(BuildContext context) {
    final code = widget.store.code;
    return MaterialApp(
      title: 'Bên Nhau',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF0457D),
        ).copyWith(primary: const Color(0xFFF0457D)),
      ),
      home: code == null
          ? PairScreen(store: widget.store, onPaired: () => setState(() {}))
          : MapScreen(
              key: ValueKey(code),
              store: widget.store,
              onLeave: () => setState(() {}),
            ),
    );
  }
}
