class Rate {
  int? id;
  String valueRate;

  Rate({this.id, required this.valueRate});

  Map<String, dynamic> toMap() {
    return {'id': id, 'valueRate': valueRate};
  }

  factory Rate.fromMap(Map<String, dynamic> map) {
    return Rate(id: map['id'], valueRate: map['valueRate']);
  }
}
