import 'package:flutter/material.dart';

import '../features/library/data/ffi_library_repository.dart';
import '../playback/player_controller.dart';
import 'mobile_shell.dart';
import 'mobius_app.dart' show ThemeModeController;
import 'mobius_shell.dart';
import 'player_shell_state.dart';

/// Chooses the shell by available width: the existing desktop [MobiusShell]
/// at `>= kMobileBreakpoint`, otherwise the phone [MobileShell]. Both take the
/// same dependencies and own player state via the shared [PlayerShellState].
///
/// The two shells are distinct subtrees, so crossing the breakpoint (e.g.
/// resizing a desktop window, or a tablet rotation) rebuilds the shell from
/// scratch and re-syncs from [PlayerController] — the controller, not the
/// widget, is the source of truth, so nothing is lost.
class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({
    super.key,
    required this.repository,
    required this.playerController,
    required this.themeController,
  });

  final FfiLibraryRepository repository;
  final PlayerController playerController;
  final ThemeModeController themeController;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= kMobileBreakpoint) {
          return MobiusShell(
            repository: repository,
            playerController: playerController,
            themeController: themeController,
          );
        }
        return MobileShell(
          repository: repository,
          playerController: playerController,
          themeController: themeController,
        );
      },
    );
  }
}
