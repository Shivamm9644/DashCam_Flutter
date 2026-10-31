import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/dashboard_provider.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/services/api_service.dart';

class FleetScreen extends StatefulWidget {
  const FleetScreen({super.key});

  @override
  State<FleetScreen> createState() => _FleetScreenState();
}

class _FleetScreenState extends State<FleetScreen> {
  String _filter = 'ALL';
  String _search = '';
  DeviceItem? _selected;

  @override
  Widget build(BuildContext context) {
    final dash = context.watch<DashboardProvider>();
    final dp = context.watch<DeviceProvider>();

    final activeDev = _selected ?? dash.selectedDevice ?? (dash.devices.isNotEmpty ? dash.devices.first : null);
    final lat = (activeDev != null && activeDev.lat != 0.0) ? activeDev.lat : 0.0;
    final lng = (activeDev != null && activeDev.lng != 0.0) ? activeDev.lng : 0.0;

    final filtered = dash.devices.where((d) {
      final matchFilter = _filter == 'ALL' || d.status == _filter;
      final matchSearch = _search.isEmpty ||
          d.plate.toLowerCase().contains(_search.toLowerCase()) ||
          d.terminalId.contains(_search) ||
          d.driver.toLowerCase().contains(_search.toLowerCase());
      return matchFilter && matchSearch;
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              color: AppTheme.bgCard,
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.map_rounded,
                          color: AppTheme.accentCyan, size: 22),
                      const SizedBox(width: 10),
                      const Text(
                        'Live Fleet & Telematics',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.statusOnline.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AppTheme.statusOnline,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${dash.onlineVehicles} ONLINE',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.statusOnline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Search
                  TextField(
                    onChanged: (v) => setState(() => _search = v),
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search plate or terminal ID...',
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: AppTheme.textMuted),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Filter pills
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['ALL', 'ONLINE', 'IDLE', 'OFFLINE']
                          .map((f) {
                        final isActive = _filter == f;
                        final color = f == 'ONLINE'
                            ? AppTheme.statusOnline
                            : f == 'IDLE'
                                ? AppTheme.statusWarning
                                : f == 'OFFLINE'
                                    ? AppTheme.statusOffline
                                    : AppTheme.accentCyan;
                        return GestureDetector(
                          onTap: () => setState(() => _filter = f),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? color.withOpacity(0.2)
                                  : AppTheme.bgCardHover,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isActive ? color : AppTheme.borderSubtle,
                                width: isActive ? 1.5 : 1,
                              ),
                            ),
                            child: Text(
                              f,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isActive ? color : AppTheme.textMuted,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

            // Real Google Maps Container
            Container(
              height: 170,
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1923),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.accentCyan.withOpacity(0.35)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // Real Google Maps Static Imagery with user's API Key (Dynamic Live GPS)
                  Positioned.fill(
                    child: Image.network(
                      'https://maps.googleapis.com/maps/api/staticmap?center=$lat,$lng&zoom=14&size=640x340&scale=2&maptype=roadmap&markers=color:0x00d4ff%7Clabel:V%7C$lat,$lng&key=${ApiService.googleMapsApiKey}',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => CustomPaint(
                        painter: _MapGridPainter(),
                        size: Size.infinite,
                      ),
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.accentCyan,
                          ),
                        );
                      },
                    ),
                  ),

                  // Google Maps Branding Badge
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.accentCyan.withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.map_rounded, color: AppTheme.accentCyan, size: 12),
                          SizedBox(width: 4),
                          Text(
                            'Google Maps Live',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accentCyan,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom info banner (Real Live GPS Coordinates)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withOpacity(0.85),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on_rounded, color: AppTheme.statusOnline, size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${activeDev?.plate ?? "Active Dashcam"}: ${lat.toStringAsFixed(4)}°N, ${lng.toStringAsFixed(4)}°E • ${activeDev?.status ?? "ONLINE"}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Device target center pin
                  Positioned(
                    left: 140,
                    top: 55,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppTheme.accentCyan.withOpacity(0.25),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.accentCyan, width: 2),
                      ),
                      child: const Icon(Icons.navigation_rounded, color: AppTheme.accentCyan, size: 18),
                    ),
                  ),
                ],
              ),
            ),

            // Device list
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.search_off_rounded,
                              color: AppTheme.textMuted, size: 48),
                          SizedBox(height: 12),
                          Text('No vehicles found',
                              style: TextStyle(color: AppTheme.textMuted)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final device = filtered[i];
                        final isSelected = _selected?.id == device.id;
                        return GestureDetector(
                          onTap: () {
                            setState(() => _selected = device);
                            dash.selectDevice(device);
                            dp.selectServerDevice(device.terminalId, device.plate);
                          },
                          child: _FleetDeviceCard(
                            device: device,
                            isSelected: isSelected,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FleetDeviceCard extends StatelessWidget {
  final DeviceItem device;
  final bool isSelected;

  const _FleetDeviceCard({required this.device, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final statusColor = device.isOnline
        ? AppTheme.statusOnline
        : device.isIdle
            ? AppTheme.statusWarning
            : AppTheme.statusOffline;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? AppTheme.accentCyan : AppTheme.borderSubtle,
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: AppTheme.accentCyan.withOpacity(0.15),
                  blurRadius: 12,
                )
              ]
            : [],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.local_shipping_rounded,
                      color: statusColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            device.plate,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusBadge(
                            label: device.status,
                            color: statusColor,
                            pulsing: device.isOnline,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '🧑‍✈️ ${device.driver}',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textMuted),
                      ),
                      Text(
                        'Terminal: ${device.terminalId}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                            fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${device.speed.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Text('km/h',
                        style: TextStyle(
                            fontSize: 10, color: AppTheme.textMuted)),
                    Text(
                      device.lastPing,
                      style: const TextStyle(
                          fontSize: 10, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Expanded telemetry HUD
          if (isSelected)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              decoration: BoxDecoration(
                color: AppTheme.bgPrimary.withOpacity(0.5),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(14)),
                border: Border(
                  top: BorderSide(color: AppTheme.borderSubtle),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      _HudItem(
                          label: 'Heading',
                          value: '${device.heading.toStringAsFixed(0)}° E'),
                      _HudItem(
                          label: 'Altitude',
                          value: '${device.altitude.toStringAsFixed(0)}m'),
                      _HudItem(
                          label: 'Lat',
                          value: device.lat.toStringAsFixed(4)),
                      _HudItem(
                          label: 'Lng',
                          value: device.lng.toStringAsFixed(4)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionBtn(
                          icon: Icons.play_circle_rounded,
                          label: 'Live View',
                          color: AppTheme.accentCyan,
                          onTap: () {},
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ActionBtn(
                          icon: Icons.settings_remote_rounded,
                          label: 'Device Mgmt',
                          color: AppTheme.accentGreen,
                          onTap: () {},
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ActionBtn(
                          icon: Icons.timeline_rounded,
                          label: 'Trip History',
                          color: AppTheme.accentPurple,
                          onTap: () {},
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HudItem extends StatelessWidget {
  final String label;
  final String value;
  const _HudItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(fontSize: 9, color: AppTheme.textMuted)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x1200D4FF)
      ..strokeWidth = 1;

    for (double x = 0; x < size.width; x += 30) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
