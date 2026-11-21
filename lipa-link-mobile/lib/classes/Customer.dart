class Customer {
  int? id;
  String fullname;
  String phone;
  String email;

  Customer({
    this.id,
    required this.fullname,
    required this.phone,
    required this.email,
  });

  Map<String, dynamic> toMap() {
    return {'id': id, 'fullname': fullname, 'phone': phone, 'email': email};
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'],
      fullname: (map['fullname'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
    );
  }
}
