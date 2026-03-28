import 'dart:async';
import 'dart:io';
import 'package:logger/logger.dart';
import '../models/models.dart';

/// Service type constant.
const int kDefaultPort = 7890;

/// Discovers MusyncMIMO devices on the local network.
///
/// Uses TCP subnet scan as primary discovery method.
/// mDNS can be added later with bonsoir package.
class DeviceDiscovery {
  final Logger _logger;
  final String deviceId;
  final String deviceName;
  final String deviceType;

  final StreamController<DeviceInfo> _deviceController =
      StreamController.broadcast();
  final Map<String, DeviceInfo> _discoveredDevices = {};
  final Map<String, DateTime> _deviceTimestamps = {};

  // TCP fallback
  ServerSocket? _discoveryServer;
  Timer? _tcpScanTimer;
  Timer? _cleanupTimer;

  bool _isPublishing = false;
  bool _isScanning = false;

  // Device TTL (time to live) - remove devices not seen for this duration
  static const Duration _deviceTtl = Duration(seconds: 60);

  DeviceDiscovery({
    required this.deviceId,
    required this.deviceName,
    this.deviceType = 'phone',
    Logger? logger,
  }) : _logger = logger ?? Logger();

  // ── Public API ──

  /// Stream of discovered devices.
  Stream<DeviceInfo> get devices => _deviceController.stream;

  /// Currently known devices.
  Map<String, DeviceInfo> get discoveredDevices =>
      Map.unmodifiable(_discoveredDevices);

  /// Whether discovery is actively scanning.
  bool get isScanning => _isScanning;

  /// Whether this device is publishing its service.
  bool get isPublishing => _isPublishing;

  /// Start publishing this device as a MusyncMIMO host.
  /// Starts a TCP probe server that responds to discovery requests.
  Future<void> startPublishing({int port = kDefaultPort}) async {
    if (_isPublishing) {
      _logger.w('Already publishing');
      return;
    }

    _isPublishing = true;

    // TCP probe server (for discovery)
    try {
      _discoveryServer =
          await ServerSocket.bind(InternetAddress.anyIPv4, port + 1);
      _logger.i('TCP discovery server started on port ${port + 1}');

      _discoveryServer!.listen((Socket client) {
        client.listen((data) {
          final message = String.fromCharCodes(data).trim();
          if (message == 'MUSYNC_PROBE') {
            final response =
                'MUSYNC_RESPONSE|$deviceId|$deviceName|$deviceType|$port';
            client.write(response);
            _logger.d('Responded to TCP discovery probe');
          }
          client.close();
        });
      });
    } catch (e) {
      _logger.w('TCP discovery server failed (non-critical): $e');
    }

    _logger.i('Publishing as MusyncMIMO host on port $port');
  }

  /// Stop publishing this device's service.
  Future<void> stopPublishing() async {
    _isPublishing = false;

    // Stop TCP server
    await _discoveryServer?.close();
    _discoveryServer = null;

    _logger.i('Stopped publishing service');
  }

  /// Start scanning for MusyncMIMO devices on the network.
  Future<void> startScanning(
      {Duration interval = const Duration(seconds: 5)}) async {
    if (_isScanning) {
      _logger.w('Already scanning');
      return;
    }

    _isScanning = true;
    _logger.i('Starting device scan...');

    // Start TCP scan
    await _startTcpScan(interval: interval);

    // Start cleanup timer for stale devices
    _cleanupTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _cleanupStaleDevices();
    });
  }

  /// Stop scanning for devices.
  Future<void> stopScanning() async {
    // Stop TCP scan
    _tcpScanTimer?.cancel();
    _tcpScanTimer = null;

    // Stop cleanup timer
    _cleanupTimer?.cancel();
    _cleanupTimer = null;

    _isScanning = false;
    _logger.i('Stopped scanning');
  }

  /// Clear the list of discovered devices.
  void clearDevices() {
    _discoveredDevices.clear();
  }

  /// Get the local IP address of this device.
  Future<String?> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          // Prefer Wi-Fi interfaces
          if (interface.name.toLowerCase().contains('wlan') ||
              interface.name.toLowerCase().contains('wi-fi') ||
              interface.name.toLowerCase().contains('en0') ||
              interface.name.toLowerCase().contains('wlp') ||
              interface.name.toLowerCase().contains('eth')) {
            return addr.address;
          }
        }
      }

      // Fallback: first non-loopback IPv4
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      _logger.e('Failed to get local IP: $e');
    }
    return null;
  }

  /// Remove devices that haven't been seen for a while.
  void _cleanupStaleDevices() {
    final now = DateTime.now();
    final staleIds = <String>[];

    for (final entry in _deviceTimestamps.entries) {
      if (now.difference(entry.value) > _deviceTtl) {
        staleIds.add(entry.key);
      }
    }

    for (final id in staleIds) {
      final device = _discoveredDevices.remove(id);
      _deviceTimestamps.remove(id);
      if (device != null) {
        _logger.d('Removed stale device: ${device.name}');
      }
    }
  }

  /// Dispose resources.
  Future<void> dispose() async {
    await stopScanning();
    await stopPublishing();
    await _deviceController.close();
  }

  // ── TCP Discovery ──

  Future<void> _startTcpScan(
      {Duration interval = const Duration(seconds: 5)}) async {
    // Initial scan
    await scanSubnet();

    // Periodic scan
    _tcpScanTimer = Timer.periodic(interval, (_) async {
      await scanSubnet();
    });
  }

  /// Scan the local subnet for MusyncMIMO devices (TCP fallback).
  Future<void> scanSubnet({int port = kDefaultPort}) async {
    final localIp = await getLocalIp();
    if (localIp == null) {
      _logger.w('Cannot determine local IP for subnet scan');
      return;
    }

    // Extract subnet (assumes /24)
    final parts = localIp.split('.');
    if (parts.length != 4) return;
    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';

    _logger.i('TCP scanning subnet $subnet.1-254:${port + 1}...');

    // Scan in batches to avoid overwhelming the network
    const batchSize = 20;
    for (int batch = 0; batch < 254; batch += batchSize) {
      final futures = <Future<void>>[];

      for (int i = batch + 1;
          i <= (batch + batchSize).clamp(1, 254);
          i++) {
        final ip = '$subnet.$i';
        if (ip == localIp) continue; // Skip self

        futures.add(_probeDevice(ip, port + 1).timeout(
          const Duration(milliseconds: 1500),
          onTimeout: () {},
        ));
      }

      await Future.wait(futures);

      // Small delay between batches
      if (batch + batchSize < 254) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    _logger
        .d('TCP scan complete. Found ${_discoveredDevices.length} device(s)');
  }

  /// Probe a specific IP for a MusyncMIMO device.
  Future<void> _probeDevice(String ip, int discoveryPort) async {
    Socket? socket;
    try {
      socket = await Socket.connect(ip, discoveryPort)
          .timeout(const Duration(milliseconds: 800));

      // Send probe message
      socket.write('MUSYNC_PROBE');
      await socket.flush();

      // Wait for response
      final response = await socket.first.timeout(
        const Duration(milliseconds: 800),
      );

      final message = String.fromCharCodes(response).trim();

      if (message.startsWith('MUSYNC_RESPONSE|')) {
        final parts = message.split('|');
        if (parts.length >= 5) {
          final devId = parts[1];
          final devName = parts[2];
          final devType = parts[3];
          final devPort = int.tryParse(parts[4]) ?? kDefaultPort;

          final device = DeviceInfo(
            id: devId,
            name: devName,
            type: DeviceType.fromString(devType),
            ip: ip,
            port: devPort,
            discoveredAt: DateTime.now(),
          );

          if (!_discoveredDevices.containsKey(device.id)) {
            _discoveredDevices[device.id] = device;
            _deviceTimestamps[device.id] = DateTime.now();
            _deviceController.add(device);
            _logger.i('TCP discovered: ${device.name} at $ip:$devPort');
          } else {
            // Update timestamp for existing device
            _deviceTimestamps[device.id] = DateTime.now();
          }
        }
      }
    } on SocketException {
      // Connection refused - not a MusyncMIMO device, normal
    } on TimeoutException {
      // Timeout - device not responding, normal
    } catch (e) {
      _logger.d('Probe error for $ip: $e');
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }
}
