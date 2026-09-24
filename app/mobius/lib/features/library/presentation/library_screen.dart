import 'package:flutter/material.dart';

import '../../../app/theme/colors.dart';
import '../../../app/theme/spacing.dart';
import '../../../app/theme/typography.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(),
          const Expanded(
            child: _LibraryContent(),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 224,
      decoration: const BoxDecoration(
        color: MobiusColors.panel,
        border: Border(
          right: BorderSide(
            color: MobiusColors.border,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: MobiusSpacing.sm,
        vertical: MobiusSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: MobiusSpacing.xs,
              bottom: MobiusSpacing.xl,
            ),
            child: Text(
              'mobius',
              style: MobiusTypography.title.copyWith(
                color: Colors.white,
              ),
            ),
          ),

          const _NavItem(
            label: 'Library',
            selected: true,
          ),

          const SizedBox(height: MobiusSpacing.xs),

          const _NavItem(
            label: 'Albums',
          ),

          const _NavItem(
            label: 'Artists',
          ),

          const _NavItem(
            label: 'Playlists',
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    this.selected = false,
  });

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Material(
        color: selected
            ? MobiusColors.violetMuted
            : Colors.transparent,
        child: InkWell(
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MobiusSpacing.xs,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: MobiusTypography.label.copyWith(
                  color: selected
                      ? MobiusColors.purpleLight
                      : MobiusColors.textDim,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryContent extends StatelessWidget {
  const _LibraryContent();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(MobiusSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Library',
            style: MobiusTypography.display.copyWith(
              color: MobiusColors.text,
            ),
          ),
          const SizedBox(height: MobiusSpacing.xl),

          Text(
            'Your music',
            style: MobiusTypography.title.copyWith(
              color: MobiusColors.text,
            ),
          ),

          const SizedBox(height: MobiusSpacing.sm),

          Text(
            'Your local music collection will appear here.',
            style: MobiusTypography.body.copyWith(
              color: MobiusColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}