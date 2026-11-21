import '../func/money.dart';

class Avance {
  int? id;
  double amount;
  DateTime paidDate;
  String devise;
  int? debtId;
  int? customerId;
  String own;

  Avance({
    this.id,
    required this.amount,
    required this.paidDate,
    this.debtId,
    this.customerId,
    required this.devise,
    required this.own,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      "paidDate": paidDate.toIso8601String(),
      "debtId": debtId,
      "devise": devise,
      "customerId": customerId,
      "own": own,
    };
  }

  factory Avance.fromMap(Map<String, dynamic> map) {
    return Avance(
      id: map['id'],
      amount: toAmount(map['amount']),
      paidDate: DateTime.parse(map['paidDate']),
      debtId: map['debtId'],
      customerId: map['customerId'],
      devise: map['devise'],
      own: map['own'],
    );
  }
}
