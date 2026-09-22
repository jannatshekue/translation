class EmergencyContact {
  final String label;
  final String number;

  const EmergencyContact({required this.label, required this.number});

  Map<String, dynamic> toJson() => {'label': label, 'number': number};

  factory EmergencyContact.fromJson(Map<String, dynamic> json) => EmergencyContact(
        label: json['label'] as String,
        number: json['number'] as String,
      );
}
