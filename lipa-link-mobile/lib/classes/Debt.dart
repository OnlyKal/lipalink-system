import '../func/money.dart';

class Debt {
  int? id;
  DateTime todayDate;
  DateTime dueDate;
  double borrowedAmount;
  String devise;
  String status;
  String motif;
  int customerId;
  String own;

  Debt({
    this.id,
    required this.todayDate,
    required this.dueDate,
    required this.borrowedAmount,
    required this.devise,
    required this.status,
    required this.motif,
    required this.customerId,
    required this.own,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'todayDate': todayDate.toIso8601String(),
      'dueDate': dueDate.toIso8601String(),
      'borrowedAmount': borrowedAmount,
      "devise": devise,
      "status": status,
      "motif": motif,
      "customerId": customerId,
      "own": own,
    };
  }

  factory Debt.fromMap(Map<String, dynamic> map) {
    return Debt(
      id: map['id'],
      todayDate: DateTime.parse(map['todayDate']),
      dueDate: DateTime.parse(map['dueDate']),
      borrowedAmount: toAmount(map['borrowedAmount']),
      devise: map['devise'],
      status: map['status'],
      motif: map['motif'],
      customerId: map['customerId'],
      own: map['own'],
    );
  }
}
