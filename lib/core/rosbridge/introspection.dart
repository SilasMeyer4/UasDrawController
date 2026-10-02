/// A single field in a ROS message or service definition.
class FieldSchema {
  final String name;
  final String type; // e.g. "float64", "string", "uint8", "bool"
  final String? defaultValue;
  final bool isArray;
  final int? arraySize;
  final bool isConstant; // has a constant value like TYPE_RAPID=0
  final dynamic constantValue;
  final List<FieldSchema> subFields; // for nested messages (not deeply parsed here)

  FieldSchema({
    required this.name,
    required this.type,
    this.defaultValue,
    this.isArray = false,
    this.arraySize,
    this.isConstant = false,
    this.constantValue,
    this.subFields = const [],
  });
}

/// A parsed ROS message/service definition (request/response split).
class MessageSchema {
  final String name;
  final List<FieldSchema> fields; // for the primary block (request or full msg)
  final List<FieldSchema> constants;
  final List<FieldSchema> requestFields;
  final List<FieldSchema> responseFields;
  final bool isService;

  MessageSchema({
    required this.name,
    this.fields = const [],
    this.constants = const [],
    this.requestFields = const [],
    this.responseFields = const [],
    this.isService = false,
  });
}

/// Parse a minimal subset of ROSDRV text into [MessageSchema].
/// Supports: primitives, arrays (e.g. float32[]), constants (NAME=0), and
/// simple service separation by `---`.
MessageSchema parseRosdrv(String name, String text) {
  final lines = text.split('\n');
  bool inResponse = false;
  final req = <FieldSchema>[];
  final res = <FieldSchema>[];
  final constants = <FieldSchema>[];
  final all = <FieldSchema>[];

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#')) continue;
    if (line == '---') {
      inResponse = true;
      continue;
    }
    // Constant: NAME = value
    final eqIdx = line.indexOf('=');
    if (eqIdx > 0) {
      final left = line.substring(0, eqIdx).trim();
      final right = line.substring(eqIdx + 1).trim();
      final parts = left.split(RegExp(r'\s+'));
      if (parts.length == 2) {
        final type = parts[0];
        final fname = parts[1];
        dynamic cv;
        // Try to parse numeric/boolean
        final n = num.tryParse(right);
        if (n != null) {
          cv = n;
        } else if (right == 'true') {
          cv = true;
        } else if (right == 'false') {
          cv = false;
        } else {
          // strip quotes if any
          cv = right.replaceAll('"', '');
        }
        final fs = FieldSchema(
          name: fname,
          type: type,
          isConstant: true,
          constantValue: cv,
        );
        constants.add(fs);
        all.add(fs);
        continue;
      }
    }
    // Field: type name [default]
    final m = RegExp(r'^([^\s]+)\s+([^\s]+)(?:\s*=\s*(.+))?$').firstMatch(line);
    if (m != null) {
      final typeStr = m.group(1)!;
      final fname = m.group(2)!;
      final defv = m.group(3)?.trim();
      final isArray = typeStr.endsWith('[]');
      final baseType = isArray ? typeStr.substring(0, typeStr.length - 2) : typeStr;
      final fs = FieldSchema(
        name: fname,
        type: baseType,
        defaultValue: defv,
        isArray: isArray,
      );
      if (inResponse) {
        res.add(fs);
      } else {
        req.add(fs);
      }
      all.add(fs);
    }
  }

  final isService = text.contains('---');
  return MessageSchema(
    name: name,
    fields: isService ? req : all,
    constants: constants,
    requestFields: req,
    responseFields: res,
    isService: isService,
  );
}
