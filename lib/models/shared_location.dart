/// One person's position at a point in time, as sent to the other person.
class SharedLocation {
  const SharedLocation({
    required this.name,
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.time,
  });

  final String name;
  final double lat;
  final double lng;
  final double accuracy;
  final DateTime time;

  Map<String, dynamic> toJson() => {
        'name': name,
        'lat': lat,
        'lng': lng,
        'acc': accuracy,
        't': time.millisecondsSinceEpoch,
      };

  factory SharedLocation.fromJson(Map<String, dynamic> json) => SharedLocation(
        name: (json['name'] as String?) ?? '',
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        accuracy: ((json['acc'] as num?) ?? 0).toDouble(),
        time: DateTime.fromMillisecondsSinceEpoch((json['t'] as num).toInt()),
      );
}
