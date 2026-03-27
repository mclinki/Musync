import 'dart:async';
import 'dart:io';
import 'package:logger/logger.dart';
import 'package:multicast_dns/multicast_dns.dart';
import '../models/models.dart';

/// Service type constant.
const int kDefaultPort = 7890;

/// mDNS service type for MusyncMIMO.
const String _kServiceType = '_musync._tcp.local';

/// Discovers MusyncMIMO devices on the local network.
///
/// Uses mDNS/Zeroconf as primary discovery method,
/// with TCP subnet scan as fallback for networks where mDNS is blocked.
class DeviceDiscovery {
  final Logger _logger;
  final String deviceId;
  final String deviceName;
  final String deviceType;

  final StreamController<DeviceInfo> _deviceController =
      StreamController.broadcast();
  final Map<String, DeviceInfo> _discoveredDevices = {};

  // mDNS
  MDnsClient? _mdnsClient;
  Timer? _mdnsScanTimer;

  // TCP fallback
  ServerSocket? _discoveryServer;
  Timer? _tcpScanTimer;

  bool _isPublishing = false;
  bool _isScanning = false;

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
  /// Uses mDNS advertisement + TCP probe server as fallback.
  Future<void> startPublishing({int port = kDefaultPort}) async {
    if (_isPublishing) {
      _logger.w('Already publishing');
      return;
    }

    _isPublishing = true;

    // TCP probe server (for fallback discovery)
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
    await _discoveryServer?.close();
    _discoveryServer = null;
    _logger.i('Stopped publishing service');
  }

  /// Start scanning for MusyncMIMO devices on the network.
  /// Tries mDNS first, falls back to TCP subnet scan.
  Future<void> startScanning(
      {Duration interval = const Duration(seconds: 5)}) async {
    if (_isScanning) {
      _logger.w('Already scanning');
      return;
    }

    _isScanning = true;
    _logger.i('Starting device scan (mDNS + TCP fallback)...');

    // Start mDNS lookup
    await _startMdnsScan();

    // Start TCP fallback scan
    await _startTcpScan(interval: interval);
  }

  /// Stop scanning for devices.
  Future<void> stopScanning() async {
    _mdnsScanTimer?.cancel();
    _mdnsScanTimer = null;
    _tcpScanTimer?.cancel();
    _tcpScanTimer = null;

    try {
      _mdnsClient?.stop();
    } catch (_) {}
    _mdnsClient = null;

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
              interface.name.toLowerCase().contains('wlp')) {
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

  /// Dispose resources.
  Future<void> dispose() async {
    await stopScanning();
    await stopPublishing();
    await _deviceController.close();
  }

  // ── mDNS Discovery ──

  Future<void> _startMdnsScan() async {
    try {
      _mdnsClient = MDnsClient();
      await _mdnsClient!.start();
      _logger.i('mDNS client started, looking for $_kServiceType');

      // Initial lookup
      await _lookupMdns();

      // Periodic lookup
      _mdnsScanTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _lookupMdns(),
      );
    } catch (e) {
      _logger.w('mDNS failed to start (will use TCP fallback): $e');
    }
  }

  Future<void> _lookupMdns() async {
    if (_mdnsClient == null) return;

    try {
      await for (final PtrResourceRecord ptr
          in _mdnsClient!.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(_kServiceType),
      )) {
        // Found a service pointer, now get the SRV record
        await for (final SrvResourceRecord srv
            in _mdnsClient!.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        )) {
          // Get the IP address
          await for (final IPAddressResourceRecord ip
              in _mdnsClient!.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
          )) {
            // Get TXT records for device info
            final txtRecords = <String, String>{};
            await for (final TxtResourceRecord txt
                in _mdnsClient!.lookup<TxtResourceRecord>(
              ResourceRecordQuery.text(ptr.domainName),
            )) {
              for (final entry in txt.text.split('\n')) {
                final parts = entry.split('=');
                if (parts.length == 2) {
                  txtRecords[parts[0]] = parts[1];
                }
              }
            }

            final device = DeviceInfo.fromMdns(
              name: ptr.domainName,
              ip: ip.address.address,
              port: srv.port,
              txtRecords: txtRecords,
            );

            if (!_discoveredDevices.containsKey(device.id)) {
              _discoveredDevices[device.id] = device;
              _deviceController.add(device);
              _logger.i(
                  'mDNS discovered: ${device.name} at ${ip.address.address}:${srv.port}');
            }
          }
        }
      }
    } catch (e) {
      _logger.d('mDNS lookup error (non-critical): $e');
    }
  }

  // ── TCP Fallback Discovery ──

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

    _logger.d('TCP scanning subnet $subnet.1-254:${port + 1}...');

    final futures = <Future<void>>[];

    for (int i = 1; i <= 254; i++) {
      final ip = '$subnet.$i';
      if (ip == localIp) continue; // Skip self

      futures.add(_probeDevice(ip, port + 1).timeout(
        const Duration(milliseconds: 800),
        onTimeout: () {},
      ));
    }

    await Future.wait(futures);
  }

  /// Probe a specific IP for a MusyncMIMO device.
  Future<void> _probeDevice(String ip, int discoveryPort) async {
    try {
      final socket = await Socket.connect(ip, discoveryPort)
          .timeout(const Duration(milliseconds: 500));

      // Send probe message
      socket.write('MUSYNC_PROBE');
      await socket.flush();

      // Wait for response
      final response = await socket.first.timeout(
        const Duration(milliseconds: 500),
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
            _deviceController.add(device);
            _logger.i('TCP discovered: ${device.name} at $ip:$devPort');
          }
        }
      }

      await socket.close();
    } catch (_) {
      // Connection failed, not a MusyncMIMO device
    }
  }
}
