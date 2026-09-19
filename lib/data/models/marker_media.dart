import 'dart:convert';

/// One attachment of a user marker.
///
/// The persisted payload is a *reference* (`marker_media/<file>.<ext>`) plus a
/// small amount of metadata — never the file content itself. That keeps a
/// marker (and any JSON/GPX export of it) small, and lets the same marker be
/// restored later without carrying megabytes of base64.
class MarkerMedia {
  const MarkerMedia({
    required this.fileRef,
    required this.type,
    required this.name,
    required this.mimeType,
    required this.createdAt,
    this.bytes,
    this.durationMs,
  });

  static const String typePhoto = 'photo';
  static const String typeVoice = 'voice';
  static const String typeVideo = 'video';

  static const Set<String> supportedTypes = <String>{
    typePhoto,
    typeVoice,
    typeVideo,
  };

  /// Relative reference inside the application documents directory.
  final String fileRef;

  /// [typePhoto], [typeVoice] or [typeVideo].
  final String type;
  final String name;
  final String mimeType;
  final DateTime createdAt;

  /// File size in bytes (not the file content).
  final int? bytes;

  /// Voice note / video length, when known.
  final int? durationMs;

  bool get isPhoto => type == typePhoto;
  bool get isVoice => type == typeVoice;
  bool get isVideo => type == typeVideo;

  bool get isPlayable => isVoice || isVideo;

  /// `mm:ss` for voice notes and videos, `--:--` when the length was never
  /// recorded.
  String get durationLabel {
    final total = durationMs == null ? null : (durationMs! / 1000).round();
    if (total == null) return '--:--';
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  MarkerMedia copyWith({
    String? fileRef,
    String? type,
    String? name,
    String? mimeType,
    DateTime? createdAt,
    int? bytes,
    int? durationMs,
  }) =>
      MarkerMedia(
        fileRef: fileRef ?? this.fileRef,
        type: type ?? this.type,
        name: name ?? this.name,
        mimeType: mimeType ?? this.mimeType,
        createdAt: createdAt ?? this.createdAt,
        bytes: bytes ?? this.bytes,
        durationMs: durationMs ?? this.durationMs,
      );

  Map<String, dynamic> toMap() => {
        'file_ref': fileRef,
        'type': type,
        'name': name,
        'mime_type': mimeType,
        'created_at': createdAt.toIso8601String(),
        if (bytes != null) 'bytes': bytes,
        if (durationMs != null) 'duration_ms': durationMs,
      };

  factory MarkerMedia.fromMap(Map<String, dynamic> map) {
    final ref = map['file_ref'];
    final type = map['type'];
    if (ref is! String || ref.isEmpty || !supportedTypes.contains(type)) {
      throw const FormatException('Invalid marker media reference');
    }
    return MarkerMedia(
      fileRef: ref,
      type: type as String,
      name: map['name'] as String? ?? ref.split('/').last,
      mimeType: map['mime_type'] as String? ?? MarkerMedia.fallbackMimeType,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      bytes: (map['bytes'] as num?)?.toInt(),
      durationMs: (map['duration_ms'] as num?)?.toInt(),
    );
  }

  static const String fallbackMimeType = 'application/octet-stream';

  /// Old rows have no media at all, and one damaged attachment must never hide
  /// the whole marker: unreadable entries are skipped instead of throwing.
  static List<MarkerMedia> decodeList(dynamic value) {
    if (value == null || value == '') return const <MarkerMedia>[];
    try {
      final decoded = value is String ? jsonDecode(value) : value;
      if (decoded is! List) return const <MarkerMedia>[];
      final result = <MarkerMedia>[];
      for (final item in decoded) {
        try {
          if (item is Map) {
            result.add(MarkerMedia.fromMap(Map<String, dynamic>.from(item)));
          }
        } on FormatException {
          continue;
        } on TypeError {
          continue;
        }
      }
      return result;
    } on FormatException {
      return const <MarkerMedia>[];
    }
  }
}
