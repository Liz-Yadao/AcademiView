import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;

class WebViewScreen extends StatefulWidget {
  final String url;
  final String fileName;
  final String fileType;

  const WebViewScreen({
    Key? key,
    required this.url,
    required this.fileName,
    required this.fileType,
  }) : super(key: key);

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  WebViewController? _controller;
  bool isLoading = true;
  String? error;
  int loadingProgress = 0;
  bool _webViewSupported = false;

  @override
  void initState() {
    super.initState();
    _checkWebViewSupport();
  }

  void _checkWebViewSupport() {
    // WebView is only not supported on Flutter Web
    if (kIsWeb) {
      setState(() {
        _webViewSupported = false;
        isLoading = false;
        error = 'WebView is not supported on Flutter Web. Please use external app.';
      });
      return;
    }

    // For all other platforms (including desktop), try to initialize WebView
    _initializeWebView();
  }

  void _initializeWebView() {
    try {
      // Create the WebView controller
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {
              if (mounted) {
                setState(() {
                  loadingProgress = progress;
                });
              }
            },
            onPageStarted: (String url) {
              if (mounted) {
                setState(() {
                  isLoading = true;
                  error = null;
                });
              }
            },
            onPageFinished: (String url) {
              if (mounted) {
                setState(() {
                  isLoading = false;
                });
              }
            },
            onWebResourceError: (WebResourceError error) {
              debugPrint('WebView error: ${error.description}');
              if (mounted) {
                setState(() {
                  this.error = 'Failed to load document: ${error.description}';
                  isLoading = false;
                });
              }
            },
            onNavigationRequest: (NavigationRequest request) {
              // Allow navigation to document viewers and the document URL
              if (request.url.contains('docs.google.com') || 
                  request.url.contains('drive.google.com') ||
                  request.url.contains('view.officeapps.live.com') ||
                  request.url == widget.url ||
                  request.url == _getViewerUrl()) {
                return NavigationDecision.navigate;
              }
              return NavigationDecision.prevent;
            },
          ),
        );

      setState(() {
        _webViewSupported = true;
      });

      // Load the document
      _loadDocument();
    } catch (e) {
      debugPrint('Error initializing WebView: $e');
      setState(() {
        _webViewSupported = false;
        isLoading = false;
        error = 'WebView initialization failed: ${e.toString()}';
      });
    }
  }

  String _getViewerUrl() {
    // Try multiple viewer options for better compatibility
    final encodedUrl = Uri.encodeComponent(widget.url);
    
    // For DOCX files, try Office Online viewer first (more reliable)
    if (widget.fileType.toLowerCase() == 'docx') {
      return 'https://view.officeapps.live.com/op/embed.aspx?src=$encodedUrl';
    }
    
    // For PPTX files, also try Office Online viewer
    if (widget.fileType.toLowerCase() == 'pptx') {
      return 'https://view.officeapps.live.com/op/embed.aspx?src=$encodedUrl';
    }
    
    // Fallback to Google Docs viewer
    return 'https://docs.google.com/gview?embedded=true&url=$encodedUrl';
  }

  void _loadDocument() {
    if (_controller == null) {
      setState(() {
        error = 'WebView controller not initialized';
        isLoading = false;
      });
      return;
    }

    try {
      final viewerUrl = _getViewerUrl();
      debugPrint('Loading document in viewer: $viewerUrl');
      debugPrint('Original file URL: ${widget.url}');
      _controller!.loadRequest(Uri.parse(viewerUrl));
    } catch (e) {
      debugPrint('Error loading document: $e');
      if (mounted) {
        setState(() {
          error = 'Error loading document: ${e.toString()}';
          isLoading = false;
        });
      }
    }
  }

  Future<void> _tryAlternativeViewer() async {
    if (_controller == null) return;
    
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      // Try Google Docs viewer as fallback
      final encodedUrl = Uri.encodeComponent(widget.url);
      final fallbackUrl = 'https://docs.google.com/gview?embedded=true&url=$encodedUrl';
      debugPrint('Trying alternative viewer: $fallbackUrl');
      await _controller!.loadRequest(Uri.parse(fallbackUrl));
    } catch (e) {
      debugPrint('Alternative viewer also failed: $e');
      if (mounted) {
        setState(() {
          error = 'All viewers failed to load the document';
          isLoading = false;
        });
      }
    }
  }

  Future<void> _openInExternalApp() async {
    try {
      final uri = Uri.parse(widget.url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open file in external app'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error opening external app: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening file: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openInBrowser() async {
    try {
      final viewerUrl = _getViewerUrl();
      final uri = Uri.parse(viewerUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open in browser'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error opening in browser: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening in browser: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _refresh() {
    if (_webViewSupported && _controller != null) {
      setState(() {
        isLoading = true;
        error = null;
        loadingProgress = 0;
      });
      _loadDocument();
    }
  }

  String _getPlatformName() {
    if (kIsWeb) return 'Web';
    if (!kIsWeb) {
      try {
        if (Platform.isWindows) return 'Windows';
        if (Platform.isLinux) return 'Linux';
        if (Platform.isMacOS) return 'macOS';
        if (Platform.isAndroid) return 'Android';
        if (Platform.isIOS) return 'iOS';
      } catch (e) {
        debugPrint('Error getting platform name: $e');
      }
    }
    return 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.fileName,
              style: const TextStyle(fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.fileType.toUpperCase(),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        actions: [
          if (_webViewSupported && _controller != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refresh,
              tooltip: 'Refresh',
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'external':
                  _openInExternalApp();
                  break;
                case 'browser':
                  _openInBrowser();
                  break;
                case 'alternative':
                  _tryAlternativeViewer();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'external',
                child: Row(
                  children: [
                    Icon(Icons.open_in_new),
                    SizedBox(width: 8),
                    Text('Open in External App'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'browser',
                child: Row(
                  children: [
                    Icon(Icons.web),
                    SizedBox(width: 8),
                    Text('Open in Browser'),
                  ],
                ),
              ),
              if (_webViewSupported)
                const PopupMenuItem(
                  value: 'alternative',
                  child: Row(
                    children: [
                      Icon(Icons.swap_horiz),
                      SizedBox(width: 8),
                      Text('Try Alternative Viewer'),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // If WebView is not supported, show fallback
    if (!_webViewSupported) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.fileType.toLowerCase() == 'pptx' 
                    ? Icons.slideshow 
                    : Icons.description,
                size: 80,
                color: Colors.deepOrange,
              ),
              const SizedBox(height: 20),
              Text(
                '${widget.fileType.toUpperCase()} Viewer',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.fileName,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.orange),
                    const SizedBox(height: 8),
                    Text(
                      'Platform: ${_getPlatformName()}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error ?? 'In-app document viewing is not supported on this platform.',
                      style: const TextStyle(fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Please use one of the options below to view your document:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.web),
                  label: const Text('View in Browser'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _openInBrowser,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open in External App'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _openInExternalApp,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              const Text(
                'Error Loading Document',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _refresh,
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Try Alternative'),
                    onPressed: _tryAlternativeViewer,
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.web),
                    label: const Text('Open in Browser'),
                    onPressed: _openInBrowser,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        WebViewWidget(controller: _controller!),
        if (isLoading)
          Container(
            color: Colors.white,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.deepOrange),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Loading ${widget.fileType.toUpperCase()} document...',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$loadingProgress%',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: LinearProgressIndicator(
                      value: loadingProgress / 100,
                      backgroundColor: Colors.grey[300],
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.deepOrange),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32.0),
                    child: Text(
                      'This may take a moment for large files...',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}