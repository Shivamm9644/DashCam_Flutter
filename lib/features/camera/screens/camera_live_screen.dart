import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/providers/dashboard_provider.dart';
import '../../../core/widgets/glass_card.dart';
import '../widgets/live_player_view.dart';

class CameraLiveScreen extends StatefulWidget {
  const CameraLiveScreen({super.key});

  @override
  State<CameraLiveScreen> createState() => _CameraLiveScreenState();
}

class _CameraLiveScreenState extends State<CameraLiveScreen>
    with SingleTickerProviderStateMixin {
  late Timer _recTimer;
  late Timer _clockTimer;
  int _recSeconds = 874; // 14m 34s
  String _currentTime = '';
  bool _showShutterFlash = false;
  bool _isFullscreen = false;
  late AnimationController _pulseController;
  int _screenMode = 0; // 0 = Live Camera (On-Demand), 1 = SD Card Playback
  DateTime _selectedDate = DateTime.now();
  int _selectedClipIndex = 0;
  int _playbackChannel = 1;

  @override
  void initState() {
    super.initState();
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateClock());
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recSeconds++);
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  void _updateClock() {
    final now = DateTime.now();
    if (mounted) {
      setState(() {
        _currentTime =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      });
    }
  }

  String _formatRecTime(int totalSeconds) {
    final h = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  void dispose() {
    _recTimer.cancel();
    _clockTimer.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _triggerSnapshot(DeviceProvider dp) {
    setState(() => _showShutterFlash = true);
    HapticFeedback.mediumImpact();
    dp.takeSnapshot();

    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _showShutterFlash = false);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.bgCard,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.accentGreen),
        ),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppTheme.accentGreen, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Snapshot captured: ${dp.lastSnapshotPath}',
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _triggerEmergencyClip(DeviceProvider dp) {
    HapticFeedback.heavyImpact();
    dp.triggerEmergencyClip();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1F0C10),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.statusCritical),
        ),
        content: Row(
          children: const [
            Icon(Icons.emergency_rounded, color: AppTheme.statusCritical, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Emergency SOS Event locked! Saving 30s high-priority clip to SD & Cloud.',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dp = context.watch<DeviceProvider>();
    final dash = context.watch<DashboardProvider>();

    // Dynamic real status from central server database
    final activeDevice = dash.devices.firstWhere(
      (d) => d.terminalId == dp.systemStatus.imei,
      orElse: () => DeviceItem(
        id: dp.systemStatus.imei,
        plate: 'Dashcam ${dp.systemStatus.imei}',
        terminalId: dp.systemStatus.imei,
        driver: 'Registered Customer',
        speed: 0,
        status: dp.systemStatus.isOnline ? 'ONLINE' : 'OFFLINE',
        lat: 33.972281,
        lng: -118.088331,
        lastPing: '',
        heading: 0,
        altitude: 0,
      ),
    );
    final isDeviceOnline = activeDevice.isOnline;

    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            if (!_isFullscreen) _buildTopHeader(context, dp, isDeviceOnline),
            _buildChannelSelector(dp),
            Expanded(
              child: SingleChildScrollView(
                physics: _isFullscreen ? const NeverScrollableScrollPhysics() : null,
                child: Column(
                  children: [
                    _buildVideoViewport(dp, isDeviceOnline, dash),
                    if (!_isFullscreen) ...[
                      _buildControlToolbar(dp),
                      const SizedBox(height: 16),
                      _buildServerConnectedDevices(dash, dp),
                      const SizedBox(height: 16),
                      _buildConnectionStatusCard(dp, isDeviceOnline),
                      const SizedBox(height: 16),
                      _buildServerConnectionGuide(dp),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader(BuildContext context, DeviceProvider dp, bool isDeviceOnline) {
    final isWifi = dp.connectionMode == 'WIFI_HOTSPOT';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isDeviceOnline
                  ? AppTheme.accentCyan.withOpacity(0.15)
                  : Colors.grey.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.videocam_rounded,
              color: isDeviceOnline ? AppTheme.accentCyan : Colors.grey,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Live Dashcam Video',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDeviceOnline
                            ? AppTheme.accentGreen.withOpacity(0.2)
                            : Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isDeviceOnline
                              ? AppTheme.accentGreen.withOpacity(0.4)
                              : Colors.red.withOpacity(0.4),
                        ),
                      ),
                      child: Text(
                        isDeviceOnline ? dp.streamQuality : 'OFFLINE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: isDeviceOnline ? AppTheme.accentGreen : Colors.redAccent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      isWifi
                          ? Icons.wifi_rounded
                          : (isDeviceOnline ? Icons.cell_tower_rounded : Icons.portable_wifi_off_rounded),
                      size: 11,
                      color: isDeviceOnline ? AppTheme.accentGreen : AppTheme.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isDeviceOnline
                          ? (isWifi ? 'WiFi Direct' : '4G Cloud Live • 25 fps')
                          : 'Camera Offline • Standby',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDeviceOnline ? AppTheme.accentGreen : AppTheme.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_input_composite_rounded,
                color: AppTheme.accentCyan, size: 22),
            tooltip: 'Connection Setup',
            onPressed: () => _showConnectionConfigSheet(context, dp),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelSelector(DeviceProvider dp) {
    return Container(
      color: const Color(0xFF0C101C),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildChannelTab(
            title: 'CH1: Road Cam',
            subtitle: '1080P • ADAS',
            icon: Icons.directions_car_rounded,
            isSelected: dp.activeChannel == 1,
            onTap: () => dp.switchChannel(1),
          ),
          const SizedBox(width: 8),
          _buildChannelTab(
            title: 'CH2: Cabin Cam',
            subtitle: '720P • DMS',
            icon: Icons.face_rounded,
            isSelected: dp.activeChannel == 2,
            onTap: () => dp.switchChannel(2),
          ),
          const SizedBox(width: 8),
          _buildChannelTab(
            title: 'Dual PIP',
            subtitle: 'Split Screen',
            icon: Icons.view_sidebar_rounded,
            isSelected: dp.activeChannel == 3,
            onTap: () => dp.switchChannel(3),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelTab({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.accentCyan.withOpacity(0.18)
                : AppTheme.bgCard.withOpacity(0.4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppTheme.accentCyan : AppTheme.borderSubtle,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? AppTheme.accentCyan : AppTheme.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : AppTheme.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 9,
                        color: isSelected ? AppTheme.accentCyan : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoViewport(DeviceProvider dp, bool isOnline, DashboardProvider dash) {
    final isDual = dp.activeChannel == 3;

    return Stack(
      children: [
        // Main Video Frame
        Container(
          width: double.infinity,
          height: _isFullscreen ? MediaQuery.of(context).size.height - 100 : 250,
          color: Colors.black,
          child: dp.isStreaming
              ? (isDual
                  ? _buildDualSplitVideo(dp, isOnline, dash)
                  : _buildSingleStreamVideo(dp, isOnline, dash))
              : _buildStreamOfflinePlaceholder(dp),
        ),

        // Shutter White Flash animation on Snapshot
        if (_showShutterFlash)
          Container(
            height: _isFullscreen ? MediaQuery.of(context).size.height - 100 : 250,
            color: Colors.white.withOpacity(0.85),
          ),

        // OSD Overlays (Top Bar: REC, Timestamp, Battery, Network)
        Positioned(
          top: 10,
          left: 12,
          right: 12,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Blinking REC Indicator
              Row(
                children: [
                  FadeTransition(
                    opacity: _pulseController,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isOnline ? AppTheme.statusCritical : Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isOnline ? 'REC ${_formatRecTime(_recSeconds)}' : 'OFFLINE • STANDBY',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: isOnline ? Colors.white : Colors.redAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (dp.isEmergencyRecording) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.statusCritical,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'SOS LOCKED',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              // Live Timestamp OSD
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _currentTime,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Bottom OSD (Telemetry: Speed, GPS, Channel)
        Positioned(
          bottom: 10,
          left: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.65),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.speed_rounded, color: AppTheme.accentGreen, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${dp.gpsStatus.speed.toInt()} KM/H',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: AppTheme.accentGreen,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.location_on_rounded, color: AppTheme.accentCyan, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${dp.gpsStatus.lat.toStringAsFixed(4)}°N, ${dp.gpsStatus.lng.toStringAsFixed(4)}°E',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.white,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                Text(
                  dp.activeChannel == 1
                      ? 'CAM 1 • ROAD'
                      : dp.activeChannel == 2
                          ? 'CAM 2 • DMS'
                          : 'CAM 1+2 DUAL',
                  style: const TextStyle(
                    color: AppTheme.accentCyan,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSingleStreamVideo(DeviceProvider dp, bool isOnline, DashboardProvider dash) {
    return LivePlayerView(
      channel: dp.activeChannel,
      terminalId: dp.systemStatus.imei,
      isOnline: isOnline,
      onRefresh: () => dash.loadDevicesFromDatabase(),
    );
  }

  Widget _buildDualSplitVideo(DeviceProvider dp, bool isOnline, DashboardProvider dash) {
    return Row(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              LivePlayerView(
                channel: 1,
                terminalId: dp.systemStatus.imei,
                isOnline: isOnline,
                onRefresh: () => dash.loadDevicesFromDatabase(),
              ),
              Positioned(
                top: 40,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('CH1: ROAD',
                      style: TextStyle(color: AppTheme.accentCyan, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
        Container(width: 2, color: AppTheme.accentCyan),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              LivePlayerView(
                channel: 2,
                terminalId: dp.systemStatus.imei,
                isOnline: isOnline,
                onRefresh: () => dash.loadDevicesFromDatabase(),
              ),
              Positioned(
                top: 40,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('CH2: DRIVER',
                      style: TextStyle(color: AppTheme.accentGreen, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGraphicSimulation(bool isRoad, DeviceProvider dp) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isRoad
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFF172554), const Color(0xFF0B132B)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.accentGreen.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.accentGreen.withOpacity(0.4)),
              ),
              child: Icon(
                isRoad ? Icons.videocam_rounded : Icons.camera_rear_rounded,
                size: 36,
                color: AppTheme.accentGreen,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isRoad ? 'CH1: FRONT ROAD CAMERA' : 'CH2: REAR / CABIN CAMERA',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Live Feed: CH${isRoad ? 1 : 2} • 1080P FHD',
                style: const TextStyle(
                  color: AppTheme.accentCyan,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Waiting for 4G LTE Video packets from Device...',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdasBoundingBoxes() {
    return Stack(
      children: [
        // Target Vehicle 1 Detection Box
        Positioned(
          top: 85,
          left: 110,
          child: Container(
            width: 130,
            height: 90,
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.accentGreen, width: 2),
              borderRadius: BorderRadius.circular(4),
              color: AppTheme.accentGreen.withOpacity(0.08),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: -18,
                  left: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    color: AppTheme.accentGreen,
                    child: const Text(
                      'Car [24.5m] TTW 2.4s',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Lane Departure Overlay Guides
        Positioned(
          bottom: 30,
          left: 50,
          right: 50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 70,
                height: 3,
                color: AppTheme.accentCyan.withOpacity(0.7),
              ),
              Container(
                width: 70,
                height: 3,
                color: AppTheme.accentCyan.withOpacity(0.7),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDmsFaceOverlay() {
    return Center(
      child: Container(
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.accentCyan.withOpacity(0.8), width: 2),
          color: AppTheme.accentCyan.withOpacity(0.05),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.face_retouching_natural_rounded, color: AppTheme.accentCyan, size: 28),
            SizedBox(height: 4),
            Text(
              'Driver: Attentive',
              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
            ),
            Text(
              'Fatigue: 0.12 (Normal)',
              style: TextStyle(color: AppTheme.accentGreen, fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamOfflinePlaceholder(DeviceProvider dp) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off_rounded, color: AppTheme.textMuted, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Live Stream Paused',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap Resume to open video pipe (${dp.connectionMode})',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentCyan,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Resume Stream', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => dp.toggleStream(),
          ),
        ],
      ),
    );
  }

  Widget _buildControlToolbar(DeviceProvider dp) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Stream Play/Pause
          _buildToolButton(
            icon: dp.isStreaming ? Icons.pause_rounded : Icons.play_arrow_rounded,
            label: dp.isStreaming ? 'Pause' : 'Play',
            color: dp.isStreaming ? AppTheme.accentOrange : AppTheme.accentGreen,
            onTap: () => dp.toggleStream(),
          ),

          // Snapshot Capture
          _buildToolButton(
            icon: Icons.camera_alt_rounded,
            label: 'Snapshot (${dp.snapshotCount})',
            color: AppTheme.accentCyan,
            onTap: () => _triggerSnapshot(dp),
          ),

          // Emergency SOS Record
          _buildToolButton(
            icon: Icons.emergency_rounded,
            label: 'SOS Lock',
            color: AppTheme.statusCritical,
            onTap: () => _triggerEmergencyClip(dp),
          ),

          // Audio Mute/Unmute
          _buildToolButton(
            icon: dp.isAudioMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            label: dp.isAudioMuted ? 'Muted' : 'Audio',
            color: dp.isAudioMuted ? AppTheme.textMuted : AppTheme.accentGreen,
            onTap: () => dp.toggleAudio(),
          ),

          // Fullscreen Toggle
          _buildToolButton(
            icon: _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
            label: _isFullscreen ? 'Exit' : 'Full',
            color: Colors.white,
            onTap: () => setState(() => _isFullscreen = !_isFullscreen),
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.4)),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerConnectedDevices(DashboardProvider dash, DeviceProvider dp) {
    final onlineCount = dash.devices.where((d) => d.isOnline).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassCard(
        borderColor: AppTheme.accentCyan.withOpacity(0.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.accentCyan.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.cloud_sync_rounded, color: AppTheme.accentCyan, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Connected Server Devices',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const Text(
                        'Central MDVR Cloud Relay',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accentGreen.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.accentGreen.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppTheme.accentGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$onlineCount ONLINE',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.accentGreen,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: AppTheme.accentCyan, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Refresh Devices',
                  onPressed: () {
                    dash.refreshStats();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Refreshing server connected devices...')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Select any device to connect and view live camera feeds:',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 10),
            ...dash.devices.map((device) {
              final isSelected = dp.systemStatus.imei == device.terminalId;
              final isOnline = device.isOnline;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accentCyan.withOpacity(0.12)
                      : AppTheme.bgPrimary.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? AppTheme.accentCyan : AppTheme.borderSubtle,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      dp.selectServerDevice(device.terminalId, device.plate, isOnline: device.isOnline);
                      dash.selectDevice(device);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: AppTheme.bgCard,
                          content: Text('Switched to ${device.plate} (${device.terminalId}) • ${device.status}'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isOnline
                                  ? AppTheme.accentGreen.withOpacity(0.15)
                                  : AppTheme.textMuted.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.videocam_rounded,
                              color: isOnline ? AppTheme.accentGreen : AppTheme.textMuted,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        device.plate,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected ? Colors.white : AppTheme.textPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isOnline
                                            ? AppTheme.accentGreen.withOpacity(0.18)
                                            : Colors.grey.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: isOnline
                                              ? AppTheme.accentGreen.withOpacity(0.4)
                                              : Colors.grey.withOpacity(0.4),
                                        ),
                                      ),
                                      child: Text(
                                        device.status,
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: isOnline ? AppTheme.accentGreen : Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Text(
                                      'IMEI: ${device.terminalId}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        color: AppTheme.accentCyan,
                                      ),
                                    ),
                                    const Text(' • ', style: TextStyle(color: AppTheme.textMuted)),
                                    Text(
                                      'Driver: ${device.driver}',
                                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isSelected)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.accentCyan,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_rounded, color: Colors.black, size: 14),
                                  SizedBox(width: 3),
                                  Text(
                                    'ACTIVE',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: AppTheme.textMuted,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatusCard(DeviceProvider dp, bool isDeviceOnline) {
    final isWifi = dp.connectionMode == 'WIFI_HOTSPOT';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassCard(
        borderColor: isWifi ? AppTheme.accentOrange.withOpacity(0.4) : (isDeviceOnline ? AppTheme.accentCyan.withOpacity(0.4) : Colors.red.withOpacity(0.3)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isWifi ? Icons.wifi_tethering_rounded : (isDeviceOnline ? Icons.cloud_done_rounded : Icons.cloud_off_rounded),
                  color: isWifi ? AppTheme.accentOrange : (isDeviceOnline ? AppTheme.accentCyan : Colors.redAccent),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  isWifi ? 'Active Pipe: Local Wi-Fi Direct' : 'Active Pipe: Cloud 4G JT1078 / Server',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDeviceOnline
                        ? AppTheme.accentGreen.withOpacity(0.15)
                        : Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDeviceOnline
                          ? AppTheme.accentGreen.withOpacity(0.4)
                          : Colors.red.withOpacity(0.4),
                    ),
                  ),
                  child: Text(
                    isDeviceOnline ? 'CONNECTED' : 'DISCONNECTED / OFFLINE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: isDeviceOnline ? AppTheme.accentGreen : Colors.redAccent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _infoItem('Server Gateway', isWifi ? 'Local Hotspot Gateway' : 'Inurum Cloud Relay (Secure SSL)'),
            _infoItem('Device Stream Pipe', isDeviceOnline ? 'Active Encrypted HLS (CH ${dp.activeChannel})' : 'Standby'),
            _infoItem('Resolution / Codec', '${dp.streamQuality} • H.264 / AAC'),
            _infoItem('Network Latency', isWifi ? '32ms (Direct Hotspot)' : '64ms (Cloud Server Relay)'),
            _infoItem('Terminal ID', dp.systemStatus.imei),
          ],
        ),
      ),
    );
  }

  Widget _infoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          Text(value, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildServerConnectionGuide(DeviceProvider dp) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.dns_rounded, color: AppTheme.accentCyan, size: 18),
                SizedBox(width: 8),
                Text(
                  'Enterprise Server & Dashcam Connection Steps',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildStepRow(
              step: '1',
              title: 'Dashcam Power & 4G Cloud Handshake',
              desc: 'Connect the dashcam to vehicle ignition or 12V adapter. Device boots up, activates 4G cellular data, and initiates TCP/JT808 connection with central Inurum MDVR cloud server.',
            ),
            const SizedBox(height: 10),
            _buildStepRow(
              step: '2',
              title: 'Server Device Registration & Health Check',
              desc: 'The central server verifies the terminal IMEI, synchronizes live GPS telematics, and opens dual-channel live video pipeline (CH1 Front Road & CH2 Cabin DMS).',
            ),
            const SizedBox(height: 10),
            _buildStepRow(
              step: '3',
              title: 'Multi-Device Live Video Monitoring',
              desc: 'All connected online devices appear in the Connected Server Devices panel above. Tap any device to stream real-time HD video, track telematics, and review safety alerts.',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentCyan,
                      side: const BorderSide(color: AppTheme.accentCyan),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.cloud_sync_rounded, size: 16),
                    label: const Text('4G Server Mode', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      dp.setConnectionMode('CLOUD_4G');
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Switched to Cloud 4G Server Mode')),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentOrange,
                      side: const BorderSide(color: AppTheme.accentOrange),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.wifi_tethering_rounded, size: 16),
                    label: const Text('Wi-Fi Mode', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      dp.setConnectionMode('WIFI_HOTSPOT');
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Switched to Local Wi-Fi Direct Mode (192.168.1.1)')),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepRow({required String step, required String title, required String desc}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.accentCyan.withOpacity(0.18),
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.accentCyan, width: 1.2),
          ),
          child: Text(
            step,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppTheme.accentCyan,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showConnectionConfigSheet(BuildContext context, DeviceProvider dp) {
    final ipController = TextEditingController(text: dp.deviceIp);
    final rtspController = TextEditingController(text: dp.customStreamUrl);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune_rounded, color: AppTheme.accentCyan, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Camera Stream Connection Settings',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(color: AppTheme.borderSubtle),
            const SizedBox(height: 12),
            const Text('Dashcam Local IP (Hotspot Gateway):',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            const SizedBox(height: 6),
            TextField(
              controller: ipController,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.bgPrimary,
                hintText: '192.168.1.1',
                hintStyle: const TextStyle(color: AppTheme.textMuted),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Custom RTSP / HTTP Stream URL:',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            const SizedBox(height: 6),
            TextField(
              controller: rtspController,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.bgPrimary,
                hintText: 'rtsp://192.168.1.1:554/live/ch0',
                hintStyle: const TextStyle(color: AppTheme.textMuted),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentCyan,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      dp.updateDeviceIp(ipController.text.trim());
                      dp.customStreamUrl = rtspController.text.trim();
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Stream settings saved and connected!')),
                      );
                    },
                    child: const Text('Save & Connect', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
