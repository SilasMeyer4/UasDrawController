import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:uasdraw/core/models/bindings.dart';
import 'package:uasdraw/core/models/connection_profile.dart';

void main() {
  group('presets', () {
    test('uasDraw maps commands to the wrapper node services', () {
      final bindings = Bindings.uasDraw();
      expect(bindings.get(LogicalAction.arm)?.name, '/UasDraw/arm');
      expect(bindings.get(LogicalAction.arm)?.isService, isTrue);
      expect(bindings.get(LogicalAction.arm)?.type, 'std_srvs/srv/Trigger');
      expect(bindings.get(LogicalAction.joy)?.name, '/UasDraw/joy');
      expect(bindings.get(LogicalAction.joy)?.isService, isFalse);
      expect(bindings.get(LogicalAction.drawData)?.name, '/uas_draw/data');
    });

    test('mavros preset uses real MAVROS 2.x service names and types', () {
      final bindings = Bindings.mavros();
      expect(bindings.get(LogicalAction.arm)?.name, '/mavros/cmd/arming');
      expect(bindings.get(LogicalAction.arm)?.type, 'mavros_msgs/srv/CommandBool');
      expect(bindings.get(LogicalAction.land)?.name, '/mavros/cmd/land');
      expect(bindings.get(LogicalAction.land)?.type, 'mavros_msgs/srv/CommandTOL');
      // MAVROS 2.x has no /mavros/set_mode and no /mavros/cmd/rtl service.
      expect(bindings.get(LogicalAction.offboard)?.name, '/mavros/cmd/command');
      expect(bindings.get(LogicalAction.rtl)?.name, '/mavros/cmd/command');
    });

    test('mode commands use MAV_CMD_DO_SET_MODE with PX4 custom modes', () {
      final bindings = Bindings.mavros();
      final offboard = bindings.get(LogicalAction.offboard)!;
      expect(offboard.args['command'], 176);
      expect(offboard.args['param2'], 6); // OFFBOARD
      final rtl = bindings.get(LogicalAction.rtl)!;
      expect(rtl.args['param2'], 5); // AUTO.RTL
    });

    test('CommandBool arming defaults to arming the vehicle', () {
      expect(Bindings.mavros().get(LogicalAction.arm)?.args['value'], isTrue);
    });

    test('CommandTOL land sends all required fields', () {
      final land = Bindings.mavros().get(LogicalAction.land)!;
      for (final field in ['min_pitch', 'yaw', 'latitude', 'longitude', 'altitude']) {
        expect(land.args.containsKey(field), isTrue, reason: 'missing $field');
      }
    });

    test('every logical action is bound in both presets', () {
      for (final preset in Bindings.presets.values) {
        for (final action in LogicalAction.values) {
          expect(preset.get(action), isNotNull, reason: '$action unbound');
        }
      }
    });

    test('presetName identifies stock presets and custom edits', () {
      expect(Bindings.presetName(Bindings.uasDraw()), 'uasDraw');
      expect(Bindings.presetName(Bindings.mavros()), 'mavros');
      final edited =
          Bindings.uasDraw().withOverride(LogicalAction.arm,
              const Binding.service('/other/arm', 'std_srvs/srv/Trigger'));
      expect(Bindings.presetName(edited), 'custom');
    });
  });

  group('overrides', () {
    test('withOverride replaces one action and leaves the rest alone', () {
      final edited = Bindings.uasDraw().withOverride(
        LogicalAction.battery,
        const Binding.topic('/other/batt', 'sensor_msgs/msg/BatteryState'),
      );
      expect(edited.get(LogicalAction.battery)?.name, '/other/batt');
      expect(edited.get(LogicalAction.arm)?.name, '/UasDraw/arm');
    });

    test('argsWith merges caller overrides over preset defaults', () {
      const binding = Binding.service(
        '/x',
        'std_srvs/srv/Trigger',
        args: <String, dynamic>{'a': 1, 'b': 2},
      );
      expect(binding.argsWith(<String, dynamic>{'b': 3}),
          <String, dynamic>{'a': 1, 'b': 3});
    });
  });

  group('serialisation', () {
    test('bindings round-trip through JSON', () {
      final original = Bindings.mavros();
      final restored = Bindings.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(restored.toJson(), original.toJson());
    });

    test('unknown action keys are ignored', () {
      final restored = Bindings.fromJson(<String, dynamic>{
        'joy': <String, dynamic>{
          'name': '/j',
          'type': 'sensor_msgs/msg/Joy',
          'kind': 'topic',
        },
        'notAnAction': <String, dynamic>{'name': '/x'},
      });
      expect(restored.all.keys, <LogicalAction>[LogicalAction.joy]);
    });

    test('profile round-trips with its bindings', () {
      final profile = ConnectionProfile(
        name: 'Drone',
        wsUrl: 'ws://10.0.0.5:9090',
        bindings: Bindings.mavros(),
      );
      final restored = ConnectionProfile.fromJson(
        jsonDecode(jsonEncode(profile.toJson())) as Map<String, dynamic>,
      );
      expect(restored.name, 'Drone');
      expect(restored.wsUrl, 'ws://10.0.0.5:9090');
      expect(restored.isMock, isFalse);
      expect(restored.bindings.get(LogicalAction.arm)?.name, '/mavros/cmd/arming');
    });

    test('a profile without bindings falls back to the uasDraw preset', () {
      final restored = ConnectionProfile.fromJson(<String, dynamic>{
        'name': 'legacy',
        'wsUrl': 'ws://localhost:9090',
      });
      expect(restored.bindings.get(LogicalAction.arm)?.name, '/UasDraw/arm');
    });

    test('copyWith keeps unspecified fields', () {
      final profile = ConnectionProfile(name: 'a', wsUrl: 'ws://x:9090');
      final copy = profile.copyWith(isMock: true);
      expect(copy.name, 'a');
      expect(copy.wsUrl, 'ws://x:9090');
      expect(copy.isMock, isTrue);
      expect(copy.bindings.get(LogicalAction.joy)?.name, '/UasDraw/joy');
    });
  });
}