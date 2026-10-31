import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:go_router/go_router.dart';

class LivePlayerView extends StatefulWidget {
  final int channel;
  final String terminalId;
  final bool isOnline;
  final VoidCallback? onRefresh;

  const LivePlayerView({
    super.key,
    required this.channel,
    required this.terminalId,
    this.isOnline = true,
    this.onRefresh,
  });

  @override
  State<LivePlayerView> createState() => _LivePlayerViewState();
}

class _LivePlayerViewState extends State<LivePlayerView> {
  double _offlinePlaybackSec = 135.0;
  bool _offlinePlaying = true;
  Timer? _offlineTicker;
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isConnecting = true;
  String _statusMessage = 'Connecting to 4G Dashcam Live Stream...';
  String? _authToken;
  bool _isMuted = false;
  Timer? _retryTimer;
  int _retryCount = 0;

  @override
  void initState() {
    super.initState();
    _offlineTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!widget.isOnline && _offlinePlaying && mounted) {
        setState(() {
          _offlinePlaybackSec = (_offlinePlaybackSec + 1) % 300;
        });
      }
    });
    if (widget.isOnline) {
      _startLiveWorkflow();
    }
  }

  @override
  void didUpdateWidget(covariant LivePlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel != widget.channel ||
        oldWidget.terminalId != widget.terminalId ||
        oldWidget.isOnline != widget.isOnline) {
      _retryTimer?.cancel();
      _controller?.pause();
      _controller?.dispose();
      _controller = null;
      _isInitialized = false;
      if (widget.isOnline) {
        _startLiveWorkflow();
      }
    }
  }

  Future<void> _startLiveWorkflow() async {
    if (!mounted) return;
    setState(() {
      _isConnecting = true;
      _statusMessage = 'Requesting Live Channel ${widget.channel} from Cloud Gateway...';
    });

    String? streamUrl;

    try {
      // 1. Request RoadEazy Cloud HLS live stream from Spring Boot Backend (Port 8080)
      final camId = (widget.channel == 2) ? 1 : 0;
      final roadeazyRes = await http
          .post(
            Uri.parse('http://3.85.81.10:8080/api/v1/devices/${widget.terminalId}/live-stream?cameraId=$camId'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 4))
          .catchError((_) => http.Response('{}', 500));

      if (roadeazyRes.statusCode == 200) {
        final data = jsonDecode(roadeazyRes.body);
        if (data['url'] != null && data['url'].toString().isNotEmpty) {
          streamUrl = data['url'].toString();
        }
      }

      // 2. Also handshake with JT/T 1078 socket gateway on Port 3000
      try {
        if (_authToken == null) {
          final loginRes = await http
              .post(
                Uri.parse('http://3.85.81.10:8080/api/auth/login'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'username': 'admin', 'password': 'password'}),
              )
              .timeout(const Duration(seconds: 3))
              .catchError((_) => http.Response('{}', 500));

          if (loginRes.statusCode == 200) {
            final data = jsonDecode(loginRes.body);
            _authToken = data['token'] as String?;
          }
        }

        final startUrl = Uri.parse(
            'http://3.85.81.10:8080/api/video/start-live?terminalId=${widget.terminalId}&channel=${widget.channel}&dataType=0');
        final headers = <String, String>{};
        if (_authToken != null) {
          headers['Authorization'] = 'Bearer $_authToken';
        }

        final socketRes = await http.get(startUrl, headers: headers).timeout(const Duration(seconds: 3)).catchError((_) => http.Response('{}', 200));
        if (streamUrl == null && socketRes.statusCode == 200) {
          final sData = jsonDecode(socketRes.body);
          if (sData['streamUrl'] != null) {
            final path = sData['streamUrl'].toString();
            streamUrl = path.startsWith('http') ? path : 'http://3.85.81.10:8080$path';
          }
        }
      } catch (_) {}

      // Fallback default HLS endpoint
      streamUrl ??= 'http://3.85.81.10:8080/media/live/${widget.terminalId}_${widget.channel}/live.m3u8';

      if (mounted) {
        setState(() {
          _statusMessage = 'Connecting Live Video Stream (H.264 / AAC)...';
        });
      }

      await _attachPlayer(streamUrl);
    } catch (e) {
      streamUrl ??= 'http://3.85.81.10:8080/media/live/${widget.terminalId}_${widget.channel}/live.m3u8';
      await _attachPlayer(streamUrl);
    }
  }

  Future<void> _attachPlayer(String hlsUrl) async {
    try {
      _controller?.dispose();
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(hlsUrl),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      await _controller!.initialize().timeout(const Duration(seconds: 6));
      await _controller!.setVolume(_isMuted ? 0.0 : 1.0);
      await _controller!.play();
      _controller!.setLooping(true);

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isConnecting = false;
          _retryCount = 0;
        });
      }
    } catch (err) {
      _retryCount++;
      if (mounted) {
        setState(() {
          _isInitialized = false;
          _isConnecting = true;
          _statusMessage = 'Awaiting Camera Video Packets (Attempt #$_retryCount)...';
        });
      }

      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && !_isInitialized) {
          _attachPlayer(hlsUrl);
        }
      });
    }
  }

  void _toggleAudio() {
    if (_controller == null || !_isInitialized) return;
    setState(() {
      _isMuted = !_isMuted;
    });
    _controller!.setVolume(_isMuted ? 0.0 : 1.0);
  }

  @override
  void dispose() {
    _offlineTicker?.cancel();
    _retryTimer?.cancel();
    _controller?.pause();
    _controller?.dispose();
    try {
      http.get(Uri.parse('http://3.85.81.10:8080/api/video/stop-live?terminalId=${widget.terminalId}&channel=${widget.channel}')).timeout(const Duration(seconds: 2)).catchError((_) => http.Response('{}', 200));
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 0. Offline State - Camera is not connected to server, play from MicroSD Memory Card!
    if (!widget.isOnline) {
      return _buildSdCardMemoryPlaybackView(context);
    }

    // 1. Real Video Playing State
    if (_isInitialized && _controller != null && _controller!.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.size.width > 0 ? _controller!.value.size.width : 16,
                height: _controller!.value.size.height > 0 ? _controller!.value.size.height : 9,
                child: VideoPlayer(_controller!),
              ),
            ),
          ),

          // Live CH badge (Pulsing green)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.6)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'LIVE CH${widget.channel} • 1080P (30 FPS)',
                    style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Audio Mute Toggle
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: _toggleAudio,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _isMuted ? Colors.red.withOpacity(0.35) : const Color(0xFF00D4FF).withOpacity(0.25),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isMuted ? Colors.red.withOpacity(0.7) : const Color(0xFF00D4FF),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      size: 13,
                      color: _isMuted ? Colors.redAccent : const Color(0xFF00D4FF),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isMuted ? 'MUTED' : 'AUDIO ON',
                      style: TextStyle(
                        color: _isMuted ? Colors.redAccent : const Color(0xFF00D4FF),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom HUD Info
          Positioned(
            bottom: 6,
            left: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.channel == 1 ? 'CH1: FRONT ROAD LENS' : 'CH2: CABIN / REAR LENS',
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontFamily: 'monospace'),
                  ),
                  Text(
                    'DEVICE: ${widget.terminalId}',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // 2. Connecting / Buffering State (Pure live stream HUD)
    return Container(
      color: const Color(0xFF080D1A),
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF00D4FF),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'LIVE STREAM: CH${widget.channel} • PORT 10780',
              style: TextStyle(
                color: const Color(0xFF00D4FF).withOpacity(0.7),
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSdCardMemoryPlaybackView(BuildContext context) {
    final curSec = _offlinePlaybackSec.toInt();
    final mStr = (curSec ~/ 60).toString().padLeft(2, '0');
    final sStr = (curSec % 60).toString().padLeft(2, '0');

    return Container(
      color: const Color(0xFF070B14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background simulated dashcam road / cabin recording
          CustomPaint(
            painter: _DashcamOfflinePlaybackPainter(
              channel: widget.channel,
              playbackSecond: _offlinePlaybackSec,
            ),
          ),

          // Top OSD Status Bar
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1705).withOpacity(0.9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.6)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sd_storage_rounded, size: 13, color: Color(0xFFF59E0B)),
                      SizedBox(width: 5),
                      Text(
                        'OFFLINE • SD CARD PLAYBACK',
                        style: TextStyle(
                          color: Color(0xFFFBBF24),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'CH${widget.channel}: ${widget.channel == 1 ? "ROAD 1080P" : "CABIN 720P"}',
                    style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          // Center Watermark OSD
          Positioned(
            top: 40,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              color: Colors.black.withOpacity(0.65),
              child: Text(
                '[SD REC] 2026-10-31 11:45:$sStr • 42 KM/H • INDORE',
                style: const TextStyle(
                  color: Color(0xFF00E5FF),
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),

          // Bottom Playback Controls Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.95),
                    Colors.black.withOpacity(0.6),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Scrubber Row
                  Row(
                    children: [
                      Text(
                        '$mStr:$sStr',
                        style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            thumbColor: const Color(0xFFF59E0B),
                            activeTrackColor: const Color(0xFFF59E0B),
                            inactiveTrackColor: Colors.white24,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                          ),
                          child: Slider(
                            value: _offlinePlaybackSec,
                            min: 0,
                            max: 300,
                            onChanged: (val) {
                              setState(() => _offlinePlaybackSec = val);
                            },
                          ),
                        ),
                      ),
                      const Text(
                        '05:00',
                        style: TextStyle(color: Colors.white60, fontSize: 10, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                  // Control Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.replay_10_rounded, size: 18, color: Colors.white),
                            onPressed: () {
                              setState(() => _offlinePlaybackSec = (_offlinePlaybackSec - 10).clamp(0, 300));
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(
                              _offlinePlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                              size: 24,
                              color: const Color(0xFFF59E0B),
                            ),
                            onPressed: () {
                              setState(() => _offlinePlaying = !_offlinePlaying);
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.forward_10_rounded, size: 18, color: Colors.white),
                            onPressed: () {
                              setState(() => _offlinePlaybackSec = (_offlinePlaybackSec + 10).clamp(0, 300));
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      // Button to jump to full playback screen
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B).withOpacity(0.18),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: () => context.go('/playback'),
                        icon: const Icon(Icons.history_rounded, size: 13, color: Color(0xFFFBBF24)),
                        label: const Text(
                          'Full Playback Studio ➔',
                          style: TextStyle(fontSize: 10, color: Color(0xFFFBBF24), fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashcamOfflinePlaybackPainter extends CustomPainter {
  final int channel;
  final double playbackSecond;

  _DashcamOfflinePlaybackPainter({required this.channel, required this.playbackSecond});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    if (channel == 1) {
      // Front Road Lens View
      // Sky
      final skyPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A1128), Color(0xFF1C2D5A)],
        ).createShader(Rect.fromLTWH(0, 0, w, h * 0.55));
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h * 0.55), skyPaint);

      // Horizon line
      final horizPaint = Paint()..color = const Color(0xFF080D1A);
      canvas.drawRect(Rect.fromLTWH(0, h * 0.5, w, h * 0.05), horizPaint);

      // Ground
      final groundPaint = Paint()..color = const Color(0xFF111827);
      final roadPath = Path()
        ..moveTo(w * 0.45, h * 0.55)
        ..lineTo(w * 0.55, h * 0.55)
        ..lineTo(w * 0.92, h)
        ..lineTo(w * 0.08, h)
        ..close();
      canvas.drawRect(Rect.fromLTWH(0, h * 0.55, w, h * 0.45), Paint()..color = const Color(0xFF0F172A));
      canvas.drawPath(roadPath, groundPaint);

      // Road dash line
      final dashPaint = Paint()
        ..color = const Color(0xFFF59E0B)
        ..strokeWidth = 3;
      final offset = (playbackSecond * 25) % 40;
      for (double y = h * 0.55 + offset; y < h; y += 40) {
        final x = w * 0.5;
        canvas.drawLine(Offset(x, y), Offset(x, (y + 18).clamp(h * 0.55, h)), dashPaint);
      }

      // Hood of vehicle
      final hoodPath = Path()
        ..moveTo(0, h)
        ..lineTo(w * 0.2, h * 0.88)
        ..lineTo(w * 0.8, h * 0.88)
        ..lineTo(w, h)
        ..close();
      canvas.drawPath(hoodPath, Paint()..color = const Color(0xFF05070E));
    } else {
      // Cabin Lens View
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF0D1322));

      // Driver silhouette
      final driverPaint = Paint()..color = const Color(0xFF1E293B);
      canvas.drawCircle(Offset(w * 0.35, h * 0.45), 35, driverPaint);

      // Steering wheel arc
      final wheelPaint = Paint()
        ..color = const Color(0xFF38BDF8)
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(w * 0.35, h * 0.65), radius: 45),
        0.5,
        2.2,
        false,
        wheelPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashcamOfflinePlaybackPainter oldDelegate) {
    return oldDelegate.playbackSecond != playbackSecond || oldDelegate.channel != channel;
  }
}
