import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

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
    // 0. Offline State - Camera is not connected to server
    if (!widget.isOnline) {
      return Container(
        color: const Color(0xFF090D18),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.redAccent.withOpacity(0.4), width: 1.5),
                ),
                child: const Icon(Icons.videocam_off_rounded, color: Colors.redAccent, size: 28),
              ),
              const SizedBox(height: 12),
              const Text(
                'Camera Offline',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Device ${widget.terminalId} (CH${widget.channel}) is currently powered OFF or 4G LTE is disconnected.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Connecting to Live Cloud Feed • Awaiting Heartbeat',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onRefresh != null) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: widget.onRefresh,
                  icon: const Icon(Icons.refresh_rounded, size: 15),
                  label: const Text('Refresh Server Status'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D4FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
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
}
