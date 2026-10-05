/// Severity levels as defined by `rcl_interfaces/msg/Log`.
enum LogSeverity {
  debug(10, 'DEBUG'),
  info(20, 'INFO'),
  warn(30, 'WARN'),
  error(40, 'ERROR'),
  fatal(50, 'FATAL'),

  /// Anything ROS sent with a level this app does not model.
  unknown(0, 'LOG');

  const LogSeverity(this.rclLevel, this.label);

  /// Value carried in the `level` field of `rcl_interfaces/msg/Log`.
  final int rclLevel;

  final String label;

  /// Maps a raw `level` field onto a severity, defaulting to [unknown] so a
  /// future rcl level still shows up instead of vanishing.
  static LogSeverity fromLevel(Object? raw) => switch (raw) {
        10 => LogSeverity.debug,
        20 => LogSeverity.info,
        30 => LogSeverity.warn,
        40 => LogSeverity.error,
        50 => LogSeverity.fatal,
        _ => LogSeverity.unknown,
      };

  bool operator >=(LogSeverity other) => rclLevel >= other.rclLevel;
}

/// One record off `/rosout`, decoded from `rcl_interfaces/msg/Log`.
class LogEntry {
  const LogEntry({
    required this.stamp,
    required this.severity,
    required this.node,
    required this.message,
  });

  /// Time the node logged, falling back to arrival time when the stamp is
  /// unusable (the fake graph, or a publisher that leaves `stamp` at zero).
  final DateTime stamp;

  final LogSeverity severity;

  /// Logger name, normally the node name such as `/uas_draw/gcode_interpreter`.
  final String node;

  final String message;

  /// `HH:MM:SS.mmm`, which is all that fits in a log row.
  String get timeLabel {
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    return '${two(stamp.hour)}:${two(stamp.minute)}:${two(stamp.second)}'
        '.${three(stamp.millisecond)}';
  }

  /// Decodes a `rcl_interfaces/msg/Log` payload.
  ///
  /// Returns `null` when the frame carries no `msg`, which is how a publisher
  /// with an unexpected type would show up; dropping it is better than showing
  /// an empty row.
  static LogEntry? fromRosout(Map<String, dynamic> msg) {
    final text = msg['msg'];
    if (text is! String) return null;
    return LogEntry(
      stamp: _stampOf(msg['stamp']),
      severity: LogSeverity.fromLevel(msg['level']),
      node: msg['name'] as String? ?? '',
      message: text,
    );
  }

  /// `builtin_interfaces/Time` arrives as `{sec, nanosec}`.
  static DateTime _stampOf(Object? raw) {
    if (raw is Map<String, dynamic>) {
      final sec = (raw['sec'] as num?)?.toInt();
      final nanos = (raw['nanosec'] as num?)?.toInt() ?? 0;
      if (sec != null && sec > 0) {
        return DateTime.fromMicrosecondsSinceEpoch(
          sec * Duration.microsecondsPerSecond + nanos ~/ 1000,
        );
      }
    }
    return DateTime.now();
  }

  @override
  String toString() => '${severity.label} [$node] $message';
}