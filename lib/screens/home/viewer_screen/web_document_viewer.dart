import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

// Conditional imports for web-specific functionality
import 'web_document_viewer_web.dart' if (dart.library.io) 'web_document_viewer_mobile.dart';

class WebDocumentViewer extends StatefulWidget {
  final String url;
  final String fileName;
  final String fileType;

  const WebDocumentViewer({
    Key? key,
    required this.url,
    required this.fileName,
    required this.fileType,
  }) : super(key: key);

  @override
  State<WebDocumentViewer> createState() => _WebDocumentViewerState();
}

class _WebDocumentViewerState extends State<WebDocumentViewer> {
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _initializeViewer();
  }

  void _initializeViewer() {
    // Initialize based on platform
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    });
  }

  String _getViewerUrl() {
    final encodedUrl = Uri.encodeComponent(widget.url);
    
    // Priority order for different file types
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

  Future<void> _openInBrowser() async {
    final viewerUrl = _getViewerUrl();
    await PlatformUtils.openUrl(viewerUrl);
  }

  Future<void> _downloadFile() async {
    await PlatformUtils.openUrl(widget.url);
  }

  void _refresh() {
    setState(() {
      isLoading = true;
      error = null;
    });
    _initializeViewer();
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: 'Refresh',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'open_browser':
                  _openInBrowser();
                  break;
                case 'download':
                  _downloadFile();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'open_browser',
                child: Row(
                  children: [
                    Icon(Icons.open_in_browser),
                    SizedBox(width: 8),
                    Text('Open in Browser'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'download',
                child: Row(
                  children: [
                    Icon(Icons.download),
                    SizedBox(width: 8),
                    Text('Download File'),
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
    if (error != null) {
      return _buildErrorView();
    }

    if (isLoading) {
      return _buildLoadingView();
    }

    // Use platform-specific implementation
    if (kIsWeb) {
      return WebDocumentViewerImpl(
        url: widget.url,
        fileName: widget.fileName,
        fileType: widget.fileType,
      );
    } else {
      return _buildMobileView();
    }
  }

  Widget _buildLoadingView() {
    return Container(
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
            const Text(
              'This may take a moment for large files...',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
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
                  icon: const Icon(Icons.open_in_browser),
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

  Widget _buildMobileView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getFileIcon(),
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
            const Text(
              'Document viewing is optimized for web browsers. Please use one of the options below:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Open in Browser'),
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
                icon: const Icon(Icons.download),
                label: const Text('Download File'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _downloadFile,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.share),
                label: const Text('Share Document'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => PlatformUtils.shareUrl(widget.url),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon() {
    switch (widget.fileType.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'docx':
      case 'doc':
        return Icons.description;
      case 'pptx':
      case 'ppt':
        return Icons.slideshow;
      case 'xlsx':
      case 'xls':
        return Icons.table_chart;
      default:
        return Icons.insert_drive_file;
    }
  }
}