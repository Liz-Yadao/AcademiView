import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

class WebDocumentViewerImpl extends StatefulWidget {
  final String url;
  final String fileName;
  final String fileType;

  const WebDocumentViewerImpl({
    Key? key,
    required this.url,
    required this.fileName,
    required this.fileType,
  }) : super(key: key);

  @override
  State<WebDocumentViewerImpl> createState() => _WebDocumentViewerImplState();
}

class _WebDocumentViewerImplState extends State<WebDocumentViewerImpl> {
  String? viewerId;
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _setupWebViewer();
  }

  void _setupWebViewer() {
    final String uniqueId = 'document-viewer-${DateTime.now().millisecondsSinceEpoch}';
    viewerId = uniqueId;

    final String viewerUrl = _getViewerUrl();
    
    try {
      ui_web.platformViewRegistry.registerViewFactory(
        uniqueId,
        (int viewId) {
          final iframe = html.IFrameElement()
            ..src = viewerUrl
            ..style.border = 'none'
            ..style.width = '100%'
            ..style.height = '100%'
            ..allowFullscreen = true;

          iframe.onLoad.listen((_) {
            if (mounted) {
              setState(() {
                isLoading = false;
              });
            }
          });

          iframe.onError.listen((_) {
            if (mounted) {
              setState(() {
                error = 'Failed to load document';
                isLoading = false;
              });
            }
          });

          return iframe;
        },
      );

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        error = 'Failed to initialize viewer: $e';
        isLoading = false;
      });
    }
  }

  String _getViewerUrl() {
    final encodedUrl = Uri.encodeComponent(widget.url);
    
    switch (widget.fileType.toLowerCase()) {
      case 'docx':
        return 'https://view.officeapps.live.com/op/embed.aspx?src=$encodedUrl';
      case 'pptx':
        return 'https://view.officeapps.live.com/op/embed.aspx?src=$encodedUrl';
      case 'pdf':
        return 'https://mozilla.github.io/pdf.js/web/viewer.html?file=$encodedUrl';
      default:
        return 'https://docs.google.com/gview?embedded=true&url=$encodedUrl';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(error!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  error = null;
                  isLoading = true;
                });
                _setupWebViewer();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.deepOrange),
        ),
      );
    }

    if (viewerId != null) {
      return HtmlElementView(viewType: viewerId!);
    }

    return const Center(
      child: Text('Failed to initialize document viewer'),
    );
  }
}

class PlatformUtils {
  static Future<void> openUrl(String url) async {
    html.window.open(url, '_blank');
  }

  static Future<void> shareUrl(String url) async {
    html.window.open(url, '_blank');
  }
}