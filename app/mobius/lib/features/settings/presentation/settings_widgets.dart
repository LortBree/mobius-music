import 'package:flutter/material.dart';

import '../../../app/player_shell_state.dart' show kMobileBreakpoint;
import '../../../app/theme/colors.dart';

/// Shared building blocks for the Settings and Sound pages, so both pages
/// keep the same header, section titles and row cards.

/// Page heading: large title plus a one-line subtitle.
class SettingsPageHeader extends StatelessWidget {
  const SettingsPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < kMobileBreakpoint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontSize: isMobile ? 32 : 42,
            fontWeight: FontWeight.w600,
            // Tight line box: the theme's default leading added ~10px of
            // empty space above the title on top of the page padding.
            height: 1.05,
            color: MobiusColors.textOf(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

/// Section heading inside a settings-style page.
class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// A bordered card with a title, a description and a trailing control.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    required this.description,
    required this.trailing,
  });

  final String title;
  final String description;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < kMobileBreakpoint;

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          description,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(height: 1.35),
        ),
      ],
    );

    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 20,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        color: MobiusColors.panelOf(context),
        border: Border.all(color: MobiusColors.borderOf(context)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                info,
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: trailing,
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: info),
                const SizedBox(width: 32),
                trailing,
              ],
            ),
    );
  }
}

/// A themed dropdown sized for a [SettingsRow] trailing slot.
class SettingsDropdown<T> extends StatelessWidget {
  const SettingsDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.labelFor,
    required this.onChanged,
  });

  final T value;
  final List<T> items;
  final String Function(T) labelFor;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < kMobileBreakpoint;
    final dropdown = DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: isMobile,
        dropdownColor: MobiusColors.panelOf(context),
        borderRadius: BorderRadius.circular(8),
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 8),
        icon: Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: MobiusColors.textDimOf(context),
          ),
        ),
        style: TextStyle(color: MobiusColors.textOf(context), fontSize: 14),
        items: [
          for (final item in items)
            DropdownMenuItem<T>(value: item, child: Text(labelFor(item))),
        ],
        onChanged: (item) {
          if (item != null) onChanged(item);
        },
      ),
    );

    if (isMobile) {
      return Container(
        height: 42,
        decoration: BoxDecoration(
          color: MobiusColors.panelOf(context),
          border: Border.all(color: MobiusColors.borderOf(context)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: dropdown,
      );
    }
    return dropdown;
  }
}
