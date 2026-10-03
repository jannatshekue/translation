class EmergencyContact {
  final String label;
  final String number;

  /// Whether this contact receives the alert when "Send alert" is pressed.
  /// Persisted so the person's choice survives closing the app.
  final bool selected;

  const EmergencyContact({required this.label, required this.number, this.selected = true});

  EmergencyContact copyWith({String? label, String? number, bool? selected}) => EmergencyContact(
        label: label ?? this.label,
        number: number ?? this.number,
        selected: selected ?? this.selected,
      );

  Map<String, dynamic> toJson() => {'label': label, 'number': number, 'selected': selected};

  // Contacts saved before selection existed have no 'selected' key — treat
  // them as selected so upgrading doesn't silently stop alerts reaching them.
  factory EmergencyContact.fromJson(Map<String, dynamic> json) => EmergencyContact(
        label: json['label'] as String,
        number: json['number'] as String,
        selected: json['selected'] as bool? ?? true,
      );
}

/// Strips spaces, dashes and brackets from a typed or phonebook number,
/// keeping digits and a leading '+'. Returns null if the result doesn't look
/// like a dialable number (at least 3 digits, e.g. "112").
String? normalizePhoneNumber(String input) {
  final trimmed = input.trim();
  final hasPlus = trimmed.startsWith('+');
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 3 || digits.length > 15) return null;
  return hasPlus ? '+$digits' : digits;
}
