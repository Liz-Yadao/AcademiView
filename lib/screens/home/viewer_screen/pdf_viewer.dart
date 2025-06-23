import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

// Proper conditional import for PDF viewer
import 'package:flutter_pdfview/flutter_pdfview.dart';

// Import the Cloudinary helper
import 'cloudinary_helper.dart';

class PdfViewerScreen extends StatefulWidget {
  final String url;
  final String fileName;
  final String? authToken;
  final Map<String, String>? customHeaders;

  const PdfViewerScreen({
    Key? key,
    required this.url,
    required this.fileName,
    this.authToken,
    this.customHeaders,
  }) : super(key: key);

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  String? localPath;
  bool isLoading = true;
  String? error;
  int currentPage = 0;
  int totalPages = 0;
  double downloadProgress = 0.0;
  bool isReady = false;
  PDFViewController? controller;

  @override
  void initState() {
    super.initState();
    _initializePdfViewer();
  }

  void _initializePdfViewer() {
    debugPrint('Initializing PDF viewer...');
    debugPrint('Platform: ${kIsWeb ? 'Web' : Platform.operatingSystem}');
    debugPrint('PDF URL: ${widget.url}');
    debugPrint('File name: ${widget.fileName}');
    
    if (kIsWeb) {
      _handleWebPlatform();
    } else {
      _downloadAndOpenPdf();
    }
  }

  void _handleWebPlatform() {
    debugPrint('Handling web platform');
    setState(() {
      isLoading = false;
      isReady = false;
    });
  }

  Future<void> _downloadAndOpenPdf() async {
    try {
      debugPrint('Starting PDF download process...');
      
      final dio = Dio();
      
      // Configure timeout and interceptors
      dio.options.connectTimeout = const Duration(minutes: 2);
      dio.options.receiveTimeout = const Duration(minutes: 5);
      dio.options.sendTimeout = const Duration(minutes: 5);
      
      // Add response interceptor for debugging
      dio.interceptors.add(InterceptorsWrapper(
        onResponse: (response, handler) {
          debugPrint('Response status: ${response.statusCode}');
          debugPrint('Response headers: ${response.headers}');
          debugPrint('Content-Type: ${response.headers.value('content-type')}');
          debugPrint('Content-Length: ${response.headers.value('content-length')}');
          handler.next(response);
        },
        onError: (error, handler) {
          debugPrint('Dio error: ${error.message}');
          debugPrint('Response: ${error.response?.data}');
          handler.next(error);
        },
      ));
      
      final dir = await getTemporaryDirectory();
      debugPrint('Temporary directory: ${dir.path}');
      
      final fileName = widget.fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final filePath = '${dir.path}/$fileName';
      debugPrint('Target file path: $filePath');
      
      // Check if file already exists and is valid
      final file = File(filePath);
      if (await file.exists()) {
        final fileSize = await file.length();
        debugPrint('Existing file found, size: $fileSize bytes');
        
        if (fileSize > 0) {
          // Verify it's a valid PDF by checking the header
          final bytes = await file.readAsBytes();
          if (bytes.length >= 5 && 
              bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) {
            debugPrint('Valid PDF file found, using cached version');
            setState(() {
              localPath = filePath;
              isLoading = false;
              isReady = true;
            });
            return;
          } else {
            debugPrint('Invalid PDF file found, deleting and re-downloading');
            await file.delete();
          }
        } else {
          debugPrint('Empty file found, deleting');
          await file.delete();
        }
      }
      
      // Generate signed URL if this is a Cloudinary URL
      String downloadUrl = widget.url;
      if (widget.url.contains('cloudinary.com')) {
        final publicId = CloudinaryHelper.extractPublicIdFromUrl(widget.url);
        if (publicId != null) {
          debugPrint('Extracted public ID: $publicId');
          downloadUrl = CloudinaryHelper.generateSignedUrl(
            publicId: publicId,
            resourceType: 'raw',
            type: 'upload',
          );
          debugPrint('Generated signed URL: $downloadUrl');
        } else {
          debugPrint('Could not extract public ID from URL: ${widget.url}');
        }
      }
      
      debugPrint('Downloading PDF from: $downloadUrl');
      
      // Prepare headers
      Map<String, String> headers = {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile; Flutter PDF Viewer) AppleWebKit/537.36',
        'Accept': 'application/pdf,application/octet-stream,*/*',
        'Accept-Encoding': 'identity', // Disable compression to avoid issues
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      };
      
      // Add authentication if provided
      if (widget.authToken != null) {
        headers['Authorization'] = 'Bearer ${widget.authToken}';
      }
      
      // Add custom headers if provided
      if (widget.customHeaders != null) {
        headers.addAll(widget.customHeaders!);
      }
      
      debugPrint('Request headers: $headers');
      
      final response = await dio.download(
        downloadUrl, 
        filePath,
        options: Options(
          headers: headers,
          followRedirects: true,
          maxRedirects: 5,
          responseType: ResponseType.bytes,
          validateStatus: (status) {
            debugPrint('Response status: $status');
            return status != null && status >= 200 && status < 300;
          },
        ),
        onReceiveProgress: (received, total) {
          if (total != -1 && mounted) {
            final progress = received / total;
            setState(() {
              downloadProgress = progress;
            });
            debugPrint('Download progress: ${(progress * 100).toInt()}% ($received/$total bytes)');
          }
        },
      );
      
      debugPrint('Download completed with status: ${response.statusCode}');
      
      // Verify the file was downloaded and has content
      if (!await file.exists()) {
        throw Exception('File was not created after download');
      }
      
      final fileSize = await file.length();
      debugPrint('Downloaded file size: $fileSize bytes');
      
      if (fileSize == 0) {
        throw Exception('Downloaded file is empty');
      }
      
      // Verify it's a valid PDF file
      final bytes = await file.readAsBytes();
      if (bytes.length < 5) {
        throw Exception('File too small to be a valid PDF');
      }
      
      // Check PDF magic number
      if (!(bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46)) {
        debugPrint('File header: ${bytes.take(10).map((b) => b.toRadixString(16)).join(' ')}');
        throw Exception('Downloaded file is not a valid PDF (invalid header)');
      }
      
      debugPrint('PDF validation successful');
      
      setState(() {
        localPath = filePath;
        isLoading = false;
        isReady = true;
      });
      
    } on DioException catch (e) {
      debugPrint('DioException details:');
      debugPrint('  Type: ${e.type}');
      debugPrint('  Message: ${e.message}');
      debugPrint('  Status code: ${e.response?.statusCode}');
      debugPrint('  Response data: ${e.response?.data}');
      
      String errorMessage = _getDioErrorMessage(e);
      
      // Special handling for 401 errors with Cloudinary
      if (e.response?.statusCode == 401 && widget.url.contains('cloudinary.com')) {
        errorMessage = 'Authentication required. Trying authenticated URL...';
        setState(() {
          error = errorMessage;
        });
        
        final publicId = CloudinaryHelper.extractPublicIdFromUrl(widget.url);
        if (publicId != null) {
          try {
            final authenticatedUrl = CloudinaryHelper.generateAuthenticatedUrl(
              publicId: publicId,
              resourceType: 'raw',
            );
            debugPrint('Retrying with authenticated URL: $authenticatedUrl');
            await _retryWithUrl(authenticatedUrl);
            return;
          } catch (retryError) {
            errorMessage = 'Authentication failed: ${retryError.toString()}';
          }
        }
      }
      
      setState(() {
        error = errorMessage;
        isLoading = false;
        isReady = false;
      });
      
    } catch (e, stackTrace) {
      debugPrint('Unexpected error downloading PDF: $e');
      debugPrint('Stack trace: $stackTrace');
      
      setState(() {
        error = 'Unexpected error: ${e.toString()}';
        isLoading = false;
        isReady = false;
      });
    }
  }

  String _getDioErrorMessage(DioException e) {
    switch (e.response?.statusCode) {
      case 400:
        return 'Bad request. The PDF URL may be invalid.';
      case 401:
        return 'Authentication required. Please check your credentials.';
      case 403:
        return 'Access forbidden. You don\'t have permission to access this PDF.';
      case 404:
        return 'PDF not found. The file may have been moved or deleted.';
      case 413:
        return 'File too large to download.';
      case 429:
        return 'Too many requests. Please try again later.';
      case 500:
      case 502:
      case 503:
      case 504:
        return 'Server error. Please try again later.';
      default:
        switch (e.type) {
          case DioExceptionType.connectionTimeout:
            return 'Connection timeout. Please check your internet connection.';
          case DioExceptionType.sendTimeout:
            return 'Send timeout. The request took too long.';
          case DioExceptionType.receiveTimeout:
            return 'Receive timeout. The download took too long.';
          case DioExceptionType.connectionError:
            return 'Connection error. Please check your internet connection.';
          case DioExceptionType.cancel:
            return 'Download was cancelled.';
          default:
            return 'Download failed: ${e.message ?? 'Unknown error'}';
        }
    }
  }

  Future<void> _retryWithUrl(String url) async {
    try {
      debugPrint('Retrying download with URL: $url');
      
      final dio = Dio();
      final dir = await getTemporaryDirectory();
      final fileName = widget.fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final filePath = '${dir.path}/$fileName';
      
      await dio.download(
        url,
        filePath,
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (compatible; Flutter PDF Viewer)',
            'Accept': 'application/pdf,*/*',
          },
          followRedirects: true,
          responseType: ResponseType.bytes,
        ),
        onReceiveProgress: (received, total) {
          if (total != -1 && mounted) {
            setState(() {
              downloadProgress = received / total;
            });
          }
        },
      );
      
      // Verify the downloaded file
      final file = File(filePath);
      final fileSize = await file.length();
      if (fileSize == 0) {
        throw Exception('Retry resulted in empty file');
      }
      
      setState(() {
        localPath = filePath;
        isLoading = false;
        isReady = true;
        error = null;
      });
      
    } catch (e) {
      debugPrint('Retry failed: $e');
      setState(() {
        error = 'Retry failed: ${e.toString()}';
        isLoading = false;
        isReady = false;
      });
    }
  }

  Future<void> _openInBrowser() async {
    try {
      String urlToOpen = widget.url;
      
      // Generate signed URL for Cloudinary if needed
      if (widget.url.contains('cloudinary.com')) {
        final publicId = CloudinaryHelper.extractPublicIdFromUrl(widget.url);
        if (publicId != null) {
          urlToOpen = CloudinaryHelper.generateDownloadUrl(
            publicId: publicId,
            resourceType: 'raw',
            filename: widget.fileName,
          );
          debugPrint('Generated browser URL: $urlToOpen');
        }
      }
      
      // Add auth token as query parameter if needed
      if (widget.authToken != null && !widget.url.contains('cloudinary.com')) {
        final uri = Uri.parse(urlToOpen);
        final newUri = uri.replace(queryParameters: {
          ...uri.queryParameters,
          'token': widget.authToken!,
        });
        urlToOpen = newUri.toString();
      }
      
      final uri = Uri.parse(urlToOpen);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Cannot launch URL: $urlToOpen');
      }
    } catch (e) {
      debugPrint('Error opening in browser: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening PDF: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.fileName,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        actions: [
          if (totalPages > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  '${currentPage + 1} / $totalPages',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            onPressed: _openInBrowser,
            tooltip: 'Open in browser',
          ),
          // Add debug info button
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: _showDebugInfo,
              tooltip: 'Debug info',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  void _showDebugInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Debug Information'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Platform: ${kIsWeb ? 'Web' : Platform.operatingSystem}'),
              Text('Original URL: ${widget.url}'),
              Text('File name: ${widget.fileName}'),
              Text('Local path: ${localPath ?? 'None'}'),
              Text('Is loading: $isLoading'),
              Text('Is ready: $isReady'),
              Text('Current page: $currentPage'),
              Text('Total pages: $totalPages'),
              Text('Download progress: ${(downloadProgress * 100).toInt()}%'),
              if (error != null) Text('Error: $error'),
              if (localPath != null) 
                FutureBuilder<bool>(
                  future: File(localPath!).exists(),
                  builder: (context, snapshot) {
                    return Text('File exists: ${snapshot.data ?? 'Checking...'}');
                  },
                ),
              if (localPath != null)
                FutureBuilder<int>(
                  future: File(localPath!).length().catchError((_) => -1),
                  builder: (context, snapshot) {
                    return Text('File size: ${snapshot.data ?? 'Checking...'} bytes');
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    // Web platform handling
    if (kIsWeb) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.picture_as_pdf,
                size: 64,
                color: Colors.deepOrange,
              ),
              const SizedBox(height: 16),
              const Text(
                'PDF Viewer',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
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
                'PDF viewing in web browser is recommended for the best experience.',
                style: TextStyle(fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('Open PDF in Browser'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _openInBrowser,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Loading state
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.deepOrange),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading PDF... ${(downloadProgress * 100).toInt()}%',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: LinearProgressIndicator(
                value: downloadProgress,
                backgroundColor: Colors.grey[300],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.deepOrange),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please wait while the PDF is being downloaded...',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Error state
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
                'Error Loading PDF',
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
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      setState(() {
                        isLoading = true;
                        error = null;
                        downloadProgress = 0.0;
                        isReady = false;
                      });
                      _downloadAndOpenPdf();
                    },
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

    // PDF is not ready
    if (!isReady || localPath == null) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.deepOrange),
        ),
      );
    }

    // Show PDF viewer (only on mobile platforms)
    return PDFView(
      filePath: localPath!,
      enableSwipe: true,
      swipeHorizontal: false,
      autoSpacing: false,
      pageFling: true,
      pageSnap: true,
      defaultPage: currentPage,
      fitPolicy: FitPolicy.BOTH,
      preventLinkNavigation: false,
      onRender: (pages) {
        debugPrint('PDF rendered with $pages pages');
        if (mounted) {
          setState(() {
            totalPages = pages ?? 0;
          });
        }
      },
      onError: (error) {
        debugPrint('PDF render error: $error');
        if (mounted) {
          setState(() {
            this.error = 'Error rendering PDF: ${error.toString()}';
            isReady = false;
          });
        }
      },
      onPageError: (page, error) {
        debugPrint('PDF page error - Page $page: $error');
        if (mounted) {
          setState(() {
            this.error = 'Error loading page $page: ${error.toString()}';
          });
        }
      },
      onPageChanged: (page, total) {
        debugPrint('Page changed to $page of $total');
        if (mounted) {
          setState(() {
            currentPage = page ?? 0;
          });
        }
      },
      onViewCreated: (PDFViewController pdfViewController) {
        debugPrint('PDF view created successfully');
        controller = pdfViewController;
      },
    );
  }

  @override
  void dispose() {
    // Clean up temporary file if needed
    if (localPath != null && !kIsWeb) {
      final file = File(localPath!);
      if (file.existsSync()) {
        try {
          file.deleteSync();
          debugPrint('Cleaned up temporary PDF file: $localPath');
        } catch (e) {
          debugPrint('Error cleaning up temporary file: $e');
        }
      }
    }
    super.dispose();
  }
}