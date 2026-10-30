import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

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
  late String _viewId;
  static final Set<String> _registeredViews = {};

  @override
  void initState() {
    super.initState();
    _viewId = 'live-dashcam-ch${widget.channel}-${widget.terminalId}';
    if (!_registeredViews.contains(_viewId)) {
      _registeredViews.add(_viewId);
      ui_web.platformViewRegistry.registerViewFactory(
        _viewId,
        (int id) => html.IFrameElement()
          ..src = '/player.html?ch=${widget.channel}&terminalId=${widget.terminalId}'
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..id = 'iframe-dashcam-ch${widget.channel}'
          ..allow = 'autoplay; fullscreen; encrypted-media; microphone',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewId);
  }
}
