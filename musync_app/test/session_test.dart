import 'package:flutter_test/flutter_test.dart';
import 'package:musync_mimo/core/models/audio_session.dart';
import 'package:musync_mimo/core/models/device_info.dart';

DeviceInfo _createDevice(String id, String name) {
  return DeviceInfo(
    id: id,
    name: name,
    type: DeviceType.phone,
    ip: '192.168.1.$id',
    port: 7890,
    discoveredAt: DateTime.now(),
  );
}

void main() {
  group('AudioSession', () {
    late DeviceInfo host;
    late AudioSession session;

    setUp(() {
      host = _createDevice('host-1', 'Host Phone');
      session = AudioSession.create(host: host);
    });

    test('creates with host device', () {
      expect(session.hostDevice.id, 'host-1');
      expect(session.slaves, isEmpty);
      expect(session.state, SessionState.waiting);
    });

    test('adds slave device', () {
      final slave = _createDevice('slave-1', 'Slave Phone');
      final updated = session.addSlave(slave);

      expect(updated.slaves.length, 1);
      expect(updated.slaves.first.id, 'slave-1');
      expect(updated.totalDevices, 2);
    });

    test('does not add duplicate device', () {
      final slave = _createDevice('slave-1', 'Slave Phone');
      final updated = session.addSlave(slave).addSlave(slave);

      expect(updated.slaves.length, 1);
    });

    test('does not add host as slave', () {
      final updated = session.addSlave(host);
      expect(updated.slaves, isEmpty);
    });

    test('removes slave device', () {
      final slave1 = _createDevice('slave-1', 'Slave 1');
      final slave2 = _createDevice('slave-2', 'Slave 2');

      final updated = session.addSlave(slave1).addSlave(slave2).removeSlave('slave-1');

      expect(updated.slaves.length, 1);
      expect(updated.slaves.first.id, 'slave-2');
    });

    test('totalDevices counts host + slaves', () {
      expect(session.totalDevices, 1);

      final withSlaves = session
          .addSlave(_createDevice('s1', 'S1'))
          .addSlave(_createDevice('s2', 'S2'));

      expect(withSlaves.totalDevices, 3);
    });

    test('isFull at 8 slaves', () {
      var s = session;
      for (int i = 0; i < 8; i++) {
        s = s.addSlave(_createDevice('slave-$i', 'Slave $i'));
      }
      expect(s.isFull, true);
      expect(s.totalDevices, 9);
    });

    test('hasDevice checks both host and slaves', () {
      final withSlave = session.addSlave(_createDevice('slave-1', 'S1'));

      expect(withSlave.hasDevice('host-1'), true);
      expect(withSlave.hasDevice('slave-1'), true);
      expect(withSlave.hasDevice('unknown'), false);
    });

    test('copyWith preserves unchanged fields', () {
      final copied = session.copyWith(state: SessionState.playing);

      expect(copied.hostDevice.id, session.hostDevice.id);
      expect(copied.sessionId, session.sessionId);
      expect(copied.state, SessionState.playing);
    });
  });

  group('SessionState', () {
    test('has correct labels', () {
      expect(SessionState.waiting.label, 'En attente');
      expect(SessionState.syncing.label, 'Synchronisation...');
      expect(SessionState.playing.label, 'En lecture');
      expect(SessionState.paused.label, 'En pause');
      expect(SessionState.buffering.label, 'Chargement...');
      expect(SessionState.error.label, 'Erreur');
    });
  });
}
