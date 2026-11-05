/// How the current reply session started.
///
/// `processText` = the user selected text in another app and chose ReplyMate
/// from the floating selection menu; `share` = the share sheet handed us
/// text; `manual` = nothing arrived, the user types or pastes.
enum LaunchSource {
  processText('process_text', 'Selected in another app'),
  share('share', 'Shared from another app'),
  manual('manual', 'Typed or pasted here');

  const LaunchSource(this.wireName, this.label);

  /// The value the native layer puts on the wire (snake_case, matching the
  /// intent actions); see docs/PLATFORM_CHANNELS.md.
  final String wireName;
  final String label;

  static LaunchSource fromName(String? name) => values.firstWhere(
    (source) => source.wireName == name || source.name == name,
    orElse: () => LaunchSource.manual,
  );
}

class LaunchContext {
  const LaunchContext({required this.source, required this.text});

  factory LaunchContext.fromMap(Map<Object?, Object?> map) {
    final text = map['text'];
    return LaunchContext(
      source: LaunchSource.fromName(map['source'] as String?),
      text: text is String ? text : '',
    );
  }

  final LaunchSource source;
  final String text;

  bool get hasText => text.trim().isNotEmpty;
}
