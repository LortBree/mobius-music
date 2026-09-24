import 'package:flutter/material.dart';

import 'theme/theme.dart';
import '../features/library/presentation/library_screen.dart';

class MobiusApp extends StatelessWidget {
  const MobiusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobius',
      debugShowCheckedModeBanner: false,
      theme: MobiusTheme.light(),
      darkTheme: MobiusTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const LibraryScreen(),
    );
  }
}