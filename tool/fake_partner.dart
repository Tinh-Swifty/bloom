// Simulates the other person for testing with a single phone:
//   dart run tool/fake_partner.dart XXXX-XXXX-XXXX [lat] [lng] [--stop] [--id=NAME]
// Run only one at a time per id: the broker bans ids that connect twice at once.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:ben_nhau/models/shared_location.dart';
import 'package:ben_nhau/services/pairing.dart';
import 'package:ben_nhau/services/sync_service.dart';

Future<void> main(List<String> args) async {
  final stop = args.contains('--stop');
  final idArg = args.where((a) => a.startsWith('--id=')).firstOrNull;
  final id = idArg?.substring(5) ?? 'fakepartner00001';
  final rest = args.where((a) => !a.startsWith('--')).toList();
  final code = rest.isEmpty ? null : Pairing.normalize(rest[0]);
  if (code == null) {
    print('usage: dart run tool/fake_partner.dart CODE [lat] [lng] [--stop]');
    exit(64);
  }
  var lat = rest.length > 1 ? double.parse(rest[1]) : 10.7769;
  var lng = rest.length > 2 ? double.parse(rest[2]) : 106.7009;

  final sync = SyncService(
    room: await Pairing.derive(code),
    deviceId: id,
  );
  sync.states.listen((s) => print('state: ${s.name}'));
  sync.partnerUpdates.listen((u) {
    final l = u.location;
    print(l == null
        ? 'app stopped sharing'
        : 'app is at ${l.lat}, ${l.lng} (${l.name})');
  });
  await sync.connect();

  if (stop) {
    sync.publishStopped();
    await Future<void>.delayed(const Duration(seconds: 2));
    await sync.dispose();
    exit(0);
  }
  for (var i = 0; i < 10; i++) {
    sync.publish(SharedLocation(
      name: 'Người ấy',
      lat: lat,
      lng: lng,
      accuracy: 8,
      time: DateTime.now(),
    ));
    print('sent $lat, $lng');
    lat += 0.0004;
    lng += 0.0003;
    await Future<void>.delayed(const Duration(seconds: 3));
  }
  await sync.dispose();
  exit(0);
}
