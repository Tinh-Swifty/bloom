import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../models/shared_location.dart';
import '../services/pairing.dart';
import '../services/session_store.dart';
import '../services/sync_service.dart';

const _meColor = Color(0xFFF0457D);
const _partnerColor = Color(0xFF8A3FD1);

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.store, required this.onLeave});

  final SessionStore store;
  final VoidCallback onLeave;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();
  SyncService? _sync;
  StreamSubscription<SyncState>? _stateSub;
  StreamSubscription<PartnerUpdate>? _partnerSub;
  StreamSubscription<Position>? _positionSub;
  Timer? _tick;

  SyncState _connection = SyncState.connecting;
  SharedLocation? _me;
  SharedLocation? _partner;
  String? _partnerId;
  bool _partnerStopped = false;
  late bool _sharing = widget.store.sharing;
  String? _locationError;
  bool _movedToFirstFix = false;

  @override
  void initState() {
    super.initState();
    // Keeps "x phút trước" fresh.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _start();
  }

  Future<void> _start() async {
    final room = await Pairing.derive(widget.store.code!);
    if (!mounted) return;
    final sync = SyncService(room: room, deviceId: widget.store.deviceId);
    _sync = sync;
    _stateSub = sync.states.listen((s) => setState(() => _connection = s));
    _partnerSub = sync.partnerUpdates.listen(_onPartner);
    if (_sharing) {
      _startLocation();
    } else {
      sync.publishStopped();
    }
    await sync.connect();
  }

  void _onPartner(PartnerUpdate update) {
    final location = update.location;
    if (location == null) {
      if (update.deviceId != _partnerId) return;
      setState(() => _partnerStopped = true);
      return;
    }
    // Only one partner: if an old device of theirs left a stale position on
    // the server, the most recent one wins.
    final current = _partner;
    if (current != null &&
        update.deviceId != _partnerId &&
        !location.time.isAfter(current.time)) {
      return;
    }
    final first = current == null || update.deviceId != _partnerId;
    setState(() {
      _partnerId = update.deviceId;
      _partner = location;
      _partnerStopped = false;
    });
    if (first) _fitBoth();
  }

  Future<void> _startLocation() async {
    await _positionSub?.cancel();
    _positionSub = null;

    if (!await Geolocator.isLocationServiceEnabled()) {
      return _failLocation('Hãy bật Dịch vụ định vị trên máy.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return _failLocation('Ứng dụng chưa được cấp quyền vị trí.');
    }
    if (!mounted || !_sharing) return;

    setState(() => _locationError = null);
    _positionSub = Geolocator.getPositionStream(
      locationSettings: _locationSettings(),
    ).listen(
      _onPosition,
      onError: (Object _) => _failLocation('Không lấy được vị trí.'),
    );
  }

  LocationSettings _locationSettings() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          intervalDuration: const Duration(seconds: 10),
          // Keeps sharing while the app is in the background.
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'Bên Nhau',
            notificationText: 'Đang chia sẻ vị trí với người ấy',
            enableWakeLock: true,
          ),
        );
      case TargetPlatform.iOS:
        return AppleSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
          pauseLocationUpdatesAutomatically: false,
        );
      default:
        return const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        );
    }
  }

  void _failLocation(String message) {
    if (mounted) setState(() => _locationError = message);
  }

  void _onPosition(Position p) {
    final me = SharedLocation(
      name: widget.store.name,
      lat: p.latitude,
      lng: p.longitude,
      accuracy: p.accuracy,
      time: DateTime.now(),
    );
    setState(() => _me = me);
    _sync?.publish(me);
    if (!_movedToFirstFix) {
      _movedToFirstFix = true;
      _partner == null ? _map.move(LatLng(me.lat, me.lng), 15) : _fitBoth();
    }
  }

  Future<void> _setSharing(bool value) async {
    setState(() => _sharing = value);
    await widget.store.setSharing(value);
    if (value) {
      await _startLocation();
    } else {
      await _positionSub?.cancel();
      _positionSub = null;
      _sync?.publishStopped();
      if (mounted) setState(() => _locationError = null);
    }
  }

  void _fitBoth() {
    final points = [
      if (_me case final m?) LatLng(m.lat, m.lng),
      if (_partner case final p?) LatLng(p.lat, p.lng),
    ];
    if (points.isEmpty) return;
    if (points.length == 1 || points.first == points.last) {
      _map.move(points.first, 15);
      return;
    }
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.fromLTRB(50, 90, 90, 260),
        maxZoom: 17,
      ),
    );
  }

  void _showCode() {
    final code = widget.store.code!;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Mã kết nối',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              SelectableText(
                code,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Chỉ gửi mã này cho người bạn muốn chia sẻ vị trí. '
                'Ai có mã đều xem được vị trí của hai bạn.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: code));
                        Navigator.pop(context);
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(content: Text('Đã sao chép mã')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Sao chép'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Builder(
                      builder: (buttonContext) => FilledButton.icon(
                        onPressed: () {
                          final box =
                              buttonContext.findRenderObject() as RenderBox?;
                          SharePlus.instance.share(
                            ShareParams(
                              text: 'Mã kết nối Bên Nhau của mình: $code',
                              sharePositionOrigin: box == null
                                  ? null
                                  : box.localToGlobal(Offset.zero) & box.size,
                            ),
                          );
                        },
                        icon: const Icon(Icons.ios_share),
                        label: const Text('Gửi mã'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ngắt kết nối?'),
        content: const Text(
          'Bạn sẽ ngừng chia sẻ vị trí và cần nhập lại mã để kết nối lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ngắt kết nối'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _positionSub?.cancel();
    _positionSub = null;
    _sync?.publishStopped();
    // Give the "stopped" message a moment to reach the server.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await widget.store.clearPairing();
    widget.onLeave();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _positionSub?.cancel();
    _stateSub?.cancel();
    _partnerSub?.cancel();
    _sync?.dispose();
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final partner = _partner;
    final mePoint = me == null ? null : LatLng(me.lat, me.lng);
    final partnerPoint =
        partner == null ? null : LatLng(partner.lat, partner.lng);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: const MapOptions(
              // Việt Nam, until the first location arrives.
              initialCenter: LatLng(16.0, 107.5),
              initialZoom: 5,
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.bennhau.ben_nhau',
              ),
              if (mePoint != null && partnerPoint != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [mePoint, partnerPoint],
                      color: _partnerColor.withValues(alpha: 0.7),
                      strokeWidth: 3,
                      pattern: const StrokePattern.dotted(),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (partnerPoint != null)
                    Marker(
                      point: partnerPoint,
                      width: 48,
                      height: 48,
                      child: _Avatar(
                        name: partner!.name,
                        color: _partnerColor,
                        faded: _partnerStopped,
                      ),
                    ),
                  if (mePoint != null)
                    Marker(
                      point: mePoint,
                      width: 48,
                      height: 48,
                      child: _Avatar(
                        name: me!.name,
                        color: _meColor,
                        faded: !_sharing,
                      ),
                    ),
                ],
              ),
              const SimpleAttributionWidget(
                source: Text('OpenStreetMap contributors'),
                alignment: Alignment.topLeft,
              ),
            ],
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MapButton(
                      icon: Icons.key,
                      tooltip: 'Mã kết nối',
                      onPressed: _showCode,
                    ),
                    const SizedBox(height: 8),
                    _MapButton(
                      icon: Icons.zoom_out_map,
                      tooltip: 'Xem cả hai',
                      onPressed: _fitBoth,
                    ),
                    const SizedBox(height: 8),
                    _MapButton(
                      icon: Icons.my_location,
                      tooltip: 'Vị trí của tôi',
                      onPressed: mePoint == null
                          ? null
                          : () => _map.move(mePoint, 16),
                    ),
                    const SizedBox(height: 8),
                    _MapButton(
                      icon: Icons.link_off,
                      tooltip: 'Ngắt kết nối',
                      onPressed: _leave,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _buildPanel(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final theme = Theme.of(context);
    final me = _me;
    final partner = _partner;

    final String title;
    final String subtitle;
    if (partner == null) {
      title = _partnerStopped
          ? 'Người ấy đang tắt chia sẻ'
          : 'Đang chờ người ấy…';
      subtitle = 'Gửi mã kết nối để người ấy nhập vào app.';
    } else {
      final distance = me == null
          ? null
          : Geolocator.distanceBetween(
              me.lat, me.lng, partner.lat, partner.lng);
      title = distance == null
          ? partner.name
          : '${partner.name} · cách ${formatDistance(distance)}';
      subtitle = _partnerStopped
          ? 'Đã tắt chia sẻ · vị trí cuối ${formatAgo(partner.time)}'
          : 'Cập nhật ${formatAgo(partner.time)}';
    }

    final (statusColor, statusText) = switch (_connection) {
      SyncState.online => (Colors.green, 'Đã kết nối'),
      SyncState.connecting => (Colors.orange, 'Đang kết nối…'),
      SyncState.offline => (Colors.red, 'Mất kết nối, đang thử lại…'),
    };

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Avatar(
                  name: partner?.name ?? '?',
                  color: _partnerColor,
                  faded: partner == null || _partnerStopped,
                  size: 44,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (partner == null)
                  IconButton.filledTonal(
                    onPressed: _showCode,
                    icon: const Icon(Icons.ios_share),
                    tooltip: 'Gửi mã',
                  ),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                Icon(Icons.circle, size: 10, color: statusColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _locationError ?? statusText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _locationError != null
                          ? theme.colorScheme.error
                          : null,
                    ),
                  ),
                ),
                Text('Chia sẻ vị trí của tôi',
                    style: theme.textTheme.bodySmall),
                const SizedBox(width: 8),
                Switch(value: _sharing, onChanged: _setSharing),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String formatDistance(double meters) => meters < 1000
    ? '${meters.round()} m'
    : '${(meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)} km';

String formatAgo(DateTime time, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(time);
  if (diff.inMinutes < 1) return 'vừa xong';
  if (diff.inHours < 1) return '${diff.inMinutes} phút trước';
  if (diff.inDays < 1) return '${diff.inHours} giờ trước';
  return '${diff.inDays} ngày trước';
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.name,
    required this.color,
    this.faded = false,
    this.size = 48,
  });

  final String name;
  final Color color;
  final bool faded;
  final double size;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: faded ? Colors.grey : color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
      ),
      child: Text(
        trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: const CircleBorder(),
      elevation: 3,
      child: IconButton(
        icon: Icon(icon),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}
