import 'package:ben_nhau/services/pairing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generated codes are valid and normalize to themselves', () {
    final code = Pairing.generateCode();
    expect(code, matches(RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$')));
    expect(Pairing.normalize(code), code);
  });

  test('normalize accepts sloppy input and rejects non-codes', () {
    expect(Pairing.normalize(' abcd efgh-jkmn '), 'ABCD-EFGH-JKMN');
    expect(Pairing.normalize('ABCD-EFGH'), isNull);
    expect(Pairing.normalize('ABCD-EFGH-JKM0'), isNull);
  });

  test('same code gives the same room; messages round-trip', () async {
    final a = await Pairing.derive('ABCD-EFGH-JKMN');
    final b = await Pairing.derive('ABCD-EFGH-JKMN');
    expect(a.topic, b.topic);

    final payload = await a.encrypt({'lat': 10.5}, 'dev1');
    expect(await b.decrypt(payload, 'dev1'), {'lat': 10.5});
    expect(await b.decrypt(payload, 'dev2'), isNull);
  });

  test('a different code cannot read the message', () async {
    final a = await Pairing.derive('ABCD-EFGH-JKMN');
    final c = await Pairing.derive('ABCD-EFGH-JKMP');
    expect(a.topic, isNot(c.topic));
    final payload = await a.encrypt({'lat': 10.5}, 'dev1');
    expect(await c.decrypt(payload, 'dev1'), isNull);
  });
}
