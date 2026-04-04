import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:logger/logger.dart';
import 'package:multicast_dns/multicast_dns.dart';
import '../app_constants.dart';
import '../models/models.dart';

/// Service type for mDNS discovery.
const String kMdnsServiceType = AppConstants.mdnsServiceType;
const int kDefaultPort = AppConstants.defaultWebSocketPort;
const String kAppVersion = AppConstants.appVersion;

/// mDNS multicast address and port.
final InternetAddress kMdnsMulticastAddress =
    InternetAddress(AppConstants.mdnsMulticastAddress);
const int kMdnsPort = AppConstants.mdnsPort;

/// Discovers MusyncMIMO devices on the local network.
///
/// Uses mDNS (multicast DNS) as primary discovery method
/// with TCP subnet scan as fallback.
class DeviceDiscovery {
  final Logger _logger;
  final String deviceId;
  String deviceName;
  final String deviceType;

  final StreamController<DeviceInfo> _deviceController =
      StreamController.broadcast();
  final Map<String, DeviceInfo> _discoveredDevices = {};
  final Map<String, DateTime> _deviceTimestamps = {};

  // mDNS
  MDnsClient? _mdnsClient;
  RawDatagramSocket? _mdnsPublishSocket;
  Timer? _mdnsQueryTimer;

  // TCP fallback
  ServerSocket? _discoveryServer;
  Timer? _tcpScanTimer;
  Timer? _cleanupTimer;

  bool _isPublishing = false;
  bool _isScanning = false;
  Uint8List? _localIpBytes;

  // Device TTL
  static const Duration _deviceTtl = Duration(seconds: AppConstants.deviceTtlSeconds);

  DeviceDiscovery({
    required this.deviceId,
    required this.deviceName,
    this.deviceType = 'phone',
    Logger? logger,
  }) : _logger = logger ?? Logger();

  // ── Public API ──

  Stream<DeviceInfo> get devices => _deviceController.stream;
  Map<String, DeviceInfo> get discoveredDevices =>
      Map.unmodifiable(_discoveredDevices);
  bool get isScanning => _isScanning;
  bool get isPublishing => _isPublishing;

  /// Start publishing this device as a MusyncMIMO host.
  /// Uses mDNS multicast responder + TCP probe server as fallback.
  Future<void> startPublishing({int port = kDefaultPort}) async {
    if (_isPublishing) {
      _logger.w('Already publishing');
      return;
    }

    _isPublishing = true;

    // 1. Start mDNS multicast responder
    await _startMdnsPublisher(port: port);

    // 2. Start TCP probe server (fallback for networks blocking multicast)
    await _startTcpProbeServer(port: port);

    _logger.i('Publishing as MusyncMIMO host on port $port');
  }

  /// Stop publishing this device's service.
  Future<void> stopPublishing() async {
    _isPublishing = false;

    _mdnsPublishSocket?.close();
    _mdnsPublishSocket = null;

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

    // 1. Start mDNS discovery (primary)
    await _startMdnsDiscovery(interval: interval);

    // 2. Start TCP subnet scan (fallback)
    await _startTcpScan(interval: interval);

    // 3. Cleanup timer for stale devices
    _cleanupTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _cleanupStaleDevices();
    });
  }

  /// Stop scanning for devices.
  Future<void> stopScanning() async {
    _mdnsClient?.stop();
    _mdnsClient = null;
    _mdnsQueryTimer?.cancel();
    _mdnsQueryTimer = null;

    _tcpScanTimer?.cancel();
    _tcpScanTimer = null;

    _cleanupTimer?.cancel();
    _cleanupTimer = null;

    _isScanning = false;
    _logger.i('Stopped scanning');
  }

  void clearDevices() {
    _discoveredDevices.clear();
  }

  /// Get the local IP address of this device.
  /// Filters out virtual adapters (VirtualBox, VMware, etc.)
  Future<String?> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      // Known virtual adapter name patterns to exclude
      const virtualPatterns = [
        'virtualbox',
        'vbox',
        'vmware',
        'vethernet',
        'hyper-v',
        'docker',
        'vnet',
        'tap-',
        'tun-',
        'hamachi',
        'zerotier',
        'tailscale',
        'wg-',
        'loopback',
        'pseudo',
      ];

      bool isVirtualName(String name) {
        final lower = name.toLowerCase();
        return virtualPatterns.any((p) => lower.contains(p));
      }

      /// Returns true if the IP belongs to a known virtual subnet.
      /// - 192.168.56.x : VirtualBox Host-Only
      /// - 172.16-31.x  : Docker / Hyper-V default ranges
      /// - 10.0.x.x     : often VPN / VM (only if adapter name is virtual)
      bool isVirtualIp(String ip) {
        return ip.startsWith('192.168.56.') ||
            ip.startsWith('172.17.') ||
            ip.startsWith('172.18.') ||
            ip.startsWith('172.19.') ||
            ip.startsWith('172.20.') ||
            ip.startsWith('172.21.') ||
            ip.startsWith('172.22.') ||
            ip.startsWith('172.23.') ||
            ip.startsWith('172.24.') ||
            ip.startsWith('172.25.') ||
            ip.startsWith('172.26.') ||
            ip.startsWith('172.27.') ||
            ip.startsWith('172.28.') ||
            ip.startsWith('172.29.') ||
            ip.startsWith('172.30.') ||
            ip.startsWith('172.31.');
      }

      bool isVirtual(String name, String ip) {
        return isVirtualName(name) || isVirtualIp(ip);
      }

      // Preferred real adapter patterns
      const realPatterns = ['wlan', 'wi-fi', 'wifi', 'en0', 'wlp', 'eth', 'net'];

      // First pass: look for known real adapters, excluding virtual ones
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (isVirtual(interface.name, addr.address)) continue;
          if (realPatterns.any((p) => interface.name.toLowerCase().contains(p))) {
            return addr.address;
          }
        }
      }

      // Second pass: any non-virtual, non-loopback address
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (isVirtual(interface.name, addr.address)) continue;
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }

      // Last resort: return first non-loopback (even if virtual)
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

  // ── mDNS Publishing ──

  /// Start a UDP multicast socket that responds to mDNS queries for our service.
  /// Includes retry logic for SocketException (CRASH-9 fix).
  Future<void> _startMdnsPublisher({int port = kDefaultPort}) async {
    // Skip mDNS on Windows (reusePort not supported)
    if (Platform.isWindows) {
      _logger.i('mDNS publisher skipped on Windows');
      return;
    }

    const maxRetries = 2;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        // Resolve local IP for the A record before publishing
        final localIp = await getLocalIp();
        if (localIp != null) {
          _localIpBytes = Uint8List.fromList(
            localIp.split('.').map(int.parse).toList(),
          );
        }

        _mdnsPublishSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          kMdnsPort,
          reuseAddress: true,
          reusePort: true,
        );

        // Join multicast group
        _mdnsPublishSocket!.joinMulticast(kMdnsMulticastAddress);

        _logger.i('mDNS publisher listening on port $kMdnsPort');

        _mdnsPublishSocket!.listen((RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            final datagram = _mdnsPublishSocket!.receive();
            if (datagram != null) {
              _handleMdnsQuery(datagram, port: port);
            }
          }
        });

        return; // Success
      } catch (e) {
        final errorStr = e.toString().toLowerCase();
        final isSocketError = errorStr.contains('socket') ||
            errorStr.contains('errno') ||
            errorStr.contains('address already in use');

        if (isSocketError && attempt < maxRetries) {
          _logger.w('mDNS publisher retry ${attempt + 1}/$maxRetries: $e');
          await Future.delayed(Duration(milliseconds: 1000 * (attempt + 1)));
        } else {
          _logger.w('mDNS publisher failed to start (non-critical): $e');
          return; // Don't crash the app
        }
      }
    }
  }

  /// Handle an incoming mDNS query and respond if it matches our service.
  void _handleMdnsQuery(Datagram datagram, {required int port}) {
    try {
      final data = datagram.data;
      if (data.length < 12) return; // Too short for DNS header

      // Parse DNS header
      final flags = (data[2] << 8) | data[3];
      final questionCount = (data[4] << 8) | data[5];

      // Only respond to queries (flags & 0x8000 == 0)
      if ((flags & 0x8000) != 0) return;
      if (questionCount == 0) return;

      // Parse questions to see if they're asking for our service
      int offset = 12;
      bool matchesOurService = false;

      for (int q = 0; q < questionCount; q++) {
        final name = _parseDnsName(data, offset);
        if (name != null) {
          offset = name.$2;
          // Skip qType (2 bytes) + qClass (2 bytes)
          offset += 4;

          // Check if query is for our service type or our specific instance
          final queryName = name.$1.toLowerCase();
          if (queryName.contains(kMdnsServiceType.toLowerCase()) ||
              queryName.contains('_musync')) {
            matchesOurService = true;
          }
        }
      }

      if (!matchesOurService) return;

      _logger.d('Received mDNS query for our service, sending response');

      // Build DNS response
      final response = _buildMdnsResponse(port: port);
      _mdnsPublishSocket!.send(response, datagram.address, datagram.port);
    } catch (e) {
      _logger.d('Error handling mDNS query: $e');
    }
  }

  /// HIGH-007 fix: Return a truncated/obfuscated device ID for mDNS broadcast.
  String _shortDeviceId() {
    if (deviceId.length <= 4) return deviceId;
    // Keep first 4 chars + hash of rest
    final hash = deviceId.hashCode.abs().toRadixString(16).substring(0, 4);
    return '${deviceId.substring(0, 4)}$hash';
  }

  /// Build an mDNS response packet for our service.
  Uint8List _buildMdnsResponse({required int port}) {
    final serviceName = '$kMdnsServiceType.local';
    final shortId = deviceId.length > 8 ? deviceId.substring(0, 8) : deviceId;
    final instanceName = '$shortId.$serviceName';
    final localName = '$deviceName.local';

    final builder = BytesBuilder();

    // DNS Header (response)
    _writeUint16(builder, 0); // Transaction ID (0 for mDNS)
    _writeUint16(builder, 0x8400); // Flags: response, authoritative
    _writeUint16(builder, 0); // Questions
    _writeUint16(builder, 3); // Answer RRs (PTR + SRV + TXT)
    _writeUint16(builder, 0); // Authority RRs
    _writeUint16(builder, 1); // Additional RRs (A record)

    // Answer 1: PTR record (_musync._tcp.local -> instance)
    _writeDnsName(builder, serviceName);
    _writeUint16(builder, 12); // TYPE: PTR
    _writeUint16(builder, 0x8001); // CLASS: IN, cache-flush
    _writeUint32(builder, 120); // TTL: 120s
    final ptrDataOffset = builder.length;
    _writeUint16(builder, 0); // Placeholder for length
    _writeDnsName(builder, instanceName);
    final ptrEnd = builder.length;
    // Write actual length
    final ptrDataLength = ptrEnd - ptrDataOffset - 2;
    final bytes = builder.toBytes();
    bytes[ptrDataOffset] = (ptrDataLength >> 8) & 0xFF;
    bytes[ptrDataOffset + 1] = ptrDataLength & 0xFF;

    // Answer 2: SRV record (instance -> host:port)
    final srvBuilder = BytesBuilder();
    _writeDnsName(srvBuilder, instanceName);
    _writeUint16(srvBuilder, 33); // TYPE: SRV
    _writeUint16(srvBuilder, 0x8001); // CLASS: IN, cache-flush
    _writeUint32(srvBuilder, 120); // TTL
    final srvDataOffset = srvBuilder.length;
    _writeUint16(srvBuilder, 0); // Placeholder
    _writeUint16(srvBuilder, 0); // Priority
    _writeUint16(srvBuilder, 0); // Weight
    _writeUint16(srvBuilder, port); // Port
    _writeDnsName(srvBuilder, localName);
    final srvDataLength = srvBuilder.length - srvDataOffset - 2;
    final srvBytes = srvBuilder.toBytes();
    srvBytes[srvDataOffset] = (srvDataLength >> 8) & 0xFF;
    srvBytes[srvDataOffset + 1] = srvDataLength & 0xFF;
    builder.add(srvBytes);

    // Answer 3: TXT record (device metadata)
    final txtBuilder = BytesBuilder();
    _writeDnsName(txtBuilder, instanceName);
    _writeUint16(txtBuilder, 16); // TYPE: TXT
    _writeUint16(txtBuilder, 0x8001); // CLASS: IN, cache-flush
    _writeUint32(txtBuilder, 120); // TTL
    final txtDataOffset = txtBuilder.length;
    _writeUint16(txtBuilder, 0); // Placeholder

    // TXT records: key=value pairs
    // HIGH-007 fix: Only broadcast minimal info in mDNS (visible to entire network)
    // Full device details are exchanged via TCP probe (requires active connection)
    final txtRecords = [
      'id=${_shortDeviceId()}', // Truncated/obfuscated ID
      'v=$kAppVersion',
    ];
    for (final record in txtRecords) {
      final recordBytes = Uint8List.fromList(record.codeUnits);
      txtBuilder.addByte(recordBytes.length);
      txtBuilder.add(recordBytes);
    }
    final txtDataLength = txtBuilder.length - txtDataOffset - 2;
    final txtBytes = txtBuilder.toBytes();
    txtBytes[txtDataOffset] = (txtDataLength >> 8) & 0xFF;
    txtBytes[txtDataOffset + 1] = txtDataLength & 0xFF;
    builder.add(txtBytes);

    // Additional: A record (local name -> IP)
    final aBuilder = BytesBuilder();
    _writeDnsName(aBuilder, localName);
    _writeUint16(aBuilder, 1); // TYPE: A
    _writeUint16(aBuilder, 0x8001); // CLASS: IN, cache-flush
    _writeUint32(aBuilder, 120); // TTL
    _writeUint16(aBuilder, 4); // RDLENGTH
    // Write IP address bytes (resolved from getLocalIp at publish time)
    aBuilder.add(_localIpBytes ?? [0, 0, 0, 0]);
    builder.add(aBuilder.toBytes());

    return builder.toBytes();
  }

  /// Parse a DNS name from a packet.
  (String, int)? _parseDnsName(Uint8List data, int offset) {
    final parts = <String>[];
    int pos = offset;

    while (pos < data.length) {
      final len = data[pos];
      if (len == 0) {
        pos++;
        break;
      }
      if ((len & 0xC0) == 0xC0) {
        // Compression pointer
        pos += 2;
        break;
      }
      pos++;
      if (pos + len > data.length) return null;
      parts.add(String.fromCharCodes(data.sublist(pos, pos + len)));
      pos += len;
    }

    return (parts.join('.'), pos);
  }

  void _writeUint16(BytesBuilder builder, int value) {
    builder.addByte((value >> 8) & 0xFF);
    builder.addByte(value & 0xFF);
  }

  void _writeUint32(BytesBuilder builder, int value) {
    builder.addByte((value >> 24) & 0xFF);
    builder.addByte((value >> 16) & 0xFF);
    builder.addByte((value >> 8) & 0xFF);
    builder.addByte(value & 0xFF);
  }

  void _writeDnsName(BytesBuilder builder, String name) {
    for (final part in name.split('.')) {
      builder.addByte(part.length);
      builder.add(Uint8List.fromList(part.codeUnits));
    }
    builder.addByte(0); // Null terminator
  }

  // ── TCP Probe Server (fallback publishing) ──

  Future<void> _startTcpProbeServer({int port = kDefaultPort}) async {
    try {
      _discoveryServer =
          await ServerSocket.bind(InternetAddress.anyIPv4, port + 1);
      _logger.i('TCP discovery server started on port ${port + 1}');

      _discoveryServer!.listen((Socket client) {
        client.listen((data) {
          final message = String.fromCharCodes(data).trim();
          if (message == 'MUSYNC_PROBE') {
            // HIGH-007 fix: Only return minimal info via TCP probe
            // Full device details exchanged via WebSocket after PIN auth
            final response =
                'MUSYNC_RESPONSE|${_shortDeviceId()}|$port';
            client.write(response);
            _logger.d('Responded to TCP discovery probe');
          }
          client.close();
        });
      });
    } catch (e) {
      _logger.w('TCP discovery server failed (non-critical): $e');
    }
  }

  // ── mDNS Discovery ──

  /// Start mDNS discovery using the multicast_dns package.
  /// CRASH-9 fix: Added retry logic + graceful degradation on SocketException.
  Future<void> _startMdnsDiscovery(
      {Duration interval = const Duration(seconds: 5)}) async {
    // mDNS is not supported on Windows (reusePort error)
    if (Platform.isWindows) {
      _logger.i('mDNS not supported on Windows, skipping');
      return;
    }

    try {
      _mdnsClient = MDnsClient();
      await _mdnsClient!.start();

      _logger.i('mDNS client started, querying for $kMdnsServiceType.local');

      // Initial query
      await _queryMdnsServices();

      // Periodic queries
      _mdnsQueryTimer = Timer.periodic(interval, (_) async {
        await _queryMdnsServices();
      });
    } catch (e) {
      // CRASH-9 fix: SocketException errno=103 is common on Android — degrade gracefully
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('socket') || errorStr.contains('errno')) {
        _logger.w('mDNS discovery failed due to socket error (CRASH-9): $e');
        _logger.w('Falling back to TCP subnet scan only');
      } else {
        _logger.w('mDNS discovery failed (non-critical): $e');
      }
      _mdnsClient = null;
    }
  }

  /// Query for mDNS services of our type.
  /// CRASH-9 fix: Wrapped in try-catch to handle SocketException during lookup.
  Future<void> _queryMdnsServices() async {
    if (_mdnsClient == null) return;

    try {
      // Query for PTR records of our service type
      await for (final ptrRecord in _mdnsClient!.lookup(
        ResourceRecordQuery.serverPointer('$kMdnsServiceType.local'),
      )) {
        if (ptrRecord is! PtrResourceRecord) continue;
        final instanceName = ptrRecord.domainName;
        _logger.d('mDNS found service instance: $instanceName');

        // Now get the SRV record for this instance
        await for (final srvRecord in _mdnsClient!.lookup(
          ResourceRecordQuery.service(instanceName),
        )) {
          if (srvRecord is! SrvResourceRecord) continue;
          final host = srvRecord.target;
          final port = srvRecord.port;

          // Get the A record for the host
          String? ip;
          await for (final aRecord in _mdnsClient!.lookup(
            ResourceRecordQuery.addressIPv4(host),
          )) {
            if (aRecord is IPAddressResourceRecord) {
              ip = aRecord.address.address;
            }
            break;
          }

          ip ??= await _resolveHostname(host);

          if (ip != null) {
            // Get TXT records for device metadata
            final txtRecords = <String, String>{};
            await for (final txtRecord in _mdnsClient!.lookup(
              ResourceRecordQuery.text(instanceName),
            )) {
              if (txtRecord is TxtResourceRecord) {
                for (final entry in txtRecord.text.split('\n')) {
                  final parts = entry.split('=');
                  if (parts.length == 2) {
                    txtRecords[parts[0]] = parts[1];
                  }
                }
              }
              break;
            }

            final devId = txtRecords['device_id'] ?? instanceName;
            final devName =
                txtRecords['device_name'] ?? _extractInstanceName(instanceName);
            final devType = txtRecords['device_type'] ?? 'phone';

            if (!_discoveredDevices.containsKey(devId)) {
              final device = DeviceInfo(
                id: devId,
                name: devName,
                type: DeviceType.fromString(devType),
                ip: ip,
                port: port,
                discoveredAt: DateTime.now(),
              );

              _discoveredDevices[devId] = device;
              _deviceTimestamps[devId] = DateTime.now();
              _deviceController.add(device);
              _logger.i('mDNS discovered: $devName at $ip:$port');
            } else {
              _deviceTimestamps[devId] = DateTime.now();
            }
          }
          break;
        }
      }
    } catch (e) {
      _logger.d('mDNS query error: $e');
    }
  }

  /// Extract instance name from FQDN (e.g., "abc12345._musync._tcp.local" -> "abc12345").
  String _extractInstanceName(String fqdn) {
    final parts = fqdn.split('.');
    return parts.isNotEmpty ? parts[0] : fqdn;
  }

  /// Try to resolve a hostname to an IP address.
  Future<String?> _resolveHostname(String hostname) async {
    try {
      // Remove trailing dot if present
      final cleanHost =
          hostname.endsWith('.') ? hostname.substring(0, hostname.length - 1) : hostname;
      final results = await InternetAddress.lookup(cleanHost);
      if (results.isNotEmpty) {
        return results.first.address;
      }
    } catch (e) {
      _logger.d('Hostname resolution failed for $hostname: $e');
    }
    return null;
  }

  // ── TCP Discovery (fallback) ──

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

    final parts = localIp.split('.');
    if (parts.length != 4) return;
    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';

    _logger.d('TCP scanning subnet $subnet.1-254:${port + 1}...');

    const batchSize = AppConstants.tcpScanBatchSize;
    for (int batch = 0; batch < 254; batch += batchSize) {
      final futures = <Future<void>>[];

      for (int i = batch + 1;
          i <= (batch + batchSize).clamp(1, 254);
          i++) {
        final ip = '$subnet.$i';
        if (ip == localIp) continue;

        futures.add(_probeDevice(ip, port + 1).timeout(
          const Duration(milliseconds: 1500),
          onTimeout: () {},
        ));
      }

      await Future.wait(futures);

      if (batch + batchSize < 254) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    _logger.d(
        'TCP scan complete. Found ${_discoveredDevices.length} device(s)');
  }

  /// Probe a specific IP for a MusyncMIMO device.
  Future<void> _probeDevice(String ip, int discoveryPort) async {
    Socket? socket;
    try {
      socket = await Socket.connect(ip, discoveryPort)
          .timeout(const Duration(milliseconds: AppConstants.probeTimeoutMs));

      socket.write('MUSYNC_PROBE');
      await socket.flush();

      final response = await socket.first.timeout(
        const Duration(milliseconds: 800),
      );

      final message = String.fromCharCodes(response).trim();

      if (message.startsWith('MUSYNC_RESPONSE|')) {
        final parts = message.split('|');
        // HIGH-007 fix: Support both old format (5 parts) and new minimal format (3 parts)
        if (parts.length >= 3) {
          final devId = parts[1];
          final devPort = parts.length >= 5
              ? (int.tryParse(parts[4]) ?? kDefaultPort) // Old format
              : (int.tryParse(parts[2]) ?? kDefaultPort); // New minimal format
          final devName = parts.length >= 5 ? parts[2] : 'Musync Device';
          final devType = parts.length >= 5 ? parts[3] : 'unknown';

          final device = DeviceInfo(
            id: devId,
            name: devName,
            type: devType != 'unknown' ? DeviceType.fromString(devType) : DeviceType.phone,
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
            _deviceTimestamps[device.id] = DateTime.now();
          }
        }
      }
    } on SocketException {
      // Connection refused - normal
    } on TimeoutException {
      // Timeout - normal
    } catch (e) {
      _logger.d('Probe error for $ip: $e');
    } finally {
      try {
        await socket?.close();
      } catch (e) {
        _logger.d('Socket close error during probe: $e');
      }
    }
  }
}
