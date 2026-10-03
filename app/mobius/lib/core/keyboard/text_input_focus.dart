import 'package:flutter/widgets.dart';

/// Whether keyboard focus is currently inside an editable text field.
///
/// App-wide playback shortcuts (Space, arrows) sit on an ancestor [Focus],
/// so key events reach them while the user is typing in a search or
/// playlist-name field. They must step aside there, or Space toggles
/// playback instead of inserting a space.
bool isEditingText() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.widget is EditableText ||
      context.findAncestorWidgetOfExactType<EditableText>() != null;
}
