import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'viewer_screen/web_view.dart';
// Add this import for your new WebDocumentViewer
import 'viewer_screen/web_document_viewer.dart'; // Uncomment when you have this file

class ModulesTab extends StatefulWidget {
  const ModulesTab({Key? key}) : super(key: key);

  @override
  State<ModulesTab> createState() => _ModulesTabState();
}

class _ModulesTabState extends State<ModulesTab> with TickerProviderStateMixin {
  bool _uploading = false;
  double _uploadProgress = 0.0;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late AnimationController _pulseController;

  // Cloudinary configuration
  static const String cloudinaryCloudName = 'dv2wqfhvt';
  static const String cloudinaryApiKey = '282553815785198';
  static const String cloudinaryApiSecret = 'ZAbmfYUOmbs8wI7dMI2ILxl_RtE';

  // Allowed file extensions - ONLY DOCX and PPTX
  static const List<String> allowedExtensions = ['pptx', 'docx'];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<String> _generateSignature(Map<String, dynamic> params) async {
    final paramsForSignature = Map<String, dynamic>.from(params);
    paramsForSignature.remove('api_key');
    
    final sortedKeys = paramsForSignature.keys.toList()..sort();
    
    final paramString = sortedKeys
        .map((key) => '$key=${paramsForSignature[key]}')
        .join('&');

    final stringToSign = '$paramString$cloudinaryApiSecret';
    
    debugPrint('String to sign: $stringToSign');

    final bytes = utf8.encode(stringToSign);
    final digest = sha1.convert(bytes);

    return digest.toString();
  }

  bool _isAllowedFileType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    return allowedExtensions.contains(extension);
  }

  Future<void> _pickAndUploadFile() async {
    final user = FirebaseAuth.instance.currentUser;
    
    if (user == null) {
      if (!mounted) return;
      _showSnackBar('Please log in to upload files', Colors.red);
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final pickedFile = result.files.single;
      
      if (!_isAllowedFileType(pickedFile.name)) {
        if (!mounted) return;
        _showSnackBar('Only PPTX and DOCX files are allowed', Colors.red);
        return;
      }
      
      Uint8List? fileBytes;
      String fileName = pickedFile.name;
      int fileSize = pickedFile.size;
      String fileType = pickedFile.extension ?? 'unknown';

      if (kIsWeb) {
        fileBytes = pickedFile.bytes;
        if (fileBytes == null) {
          if (!mounted) return;
          _showSnackBar('Could not read file data', Colors.red);
          return;
        }
      } else {
        if (pickedFile.bytes != null) {
          fileBytes = pickedFile.bytes!;
        } else {
          if (!mounted) return;
          _showSnackBar('Could not read file data', Colors.red);
          return;
        }
      }

      const maxFileSize = 50 * 1024 * 1024;
      if (fileSize > maxFileSize) {
        if (!mounted) return;
        _showSnackBar('File too large. Maximum size is 50MB', Colors.red);
        return;
      }

      if (!mounted) return;
      setState(() {
        _uploading = true;
        _uploadProgress = 0.0;
      });

      debugPrint('Starting upload for file: $fileName (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)');

      _showSnackBar('Uploading $fileName...', Colors.blue);

      final dio = Dio();
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final publicId = '${user.uid}/modules/${fileName.split('.').first}';

      final params = {
        'public_id': publicId,
        'timestamp': timestamp.toString(),
      };

      debugPrint('Generating signature for upload...');
      final signature = await _generateSignature(params);
      debugPrint('Generated signature: $signature');
      debugPrint('Public ID: $publicId');
      debugPrint('Timestamp: $timestamp');
      debugPrint('API Key: $cloudinaryApiKey');

      debugPrint('Preparing file for upload...');
      
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          fileBytes,
          filename: fileName,
        ),
        'public_id': publicId,
        'timestamp': timestamp.toString(),
        'api_key': cloudinaryApiKey,
        'signature': signature,
      });

      final uploadUrl = 'https://api.cloudinary.com/v1_1/$cloudinaryCloudName/upload';
      debugPrint('Uploading to Cloudinary: $uploadUrl');

      final response = await dio.post(
        uploadUrl,
        data: formData,
        options: Options(
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(minutes: 5),
          headers: {
            'Content-Type': 'multipart/form-data',
          },
        ),
        onSendProgress: (sent, total) {
          if (total != -1 && mounted) {
            final progress = sent / total;
            setState(() {
              _uploadProgress = progress;
            });
            debugPrint('Upload progress: ${(progress * 100).toInt()}%');
          }
        },
      );

      debugPrint('Cloudinary response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = response.data;
        
        if (responseData == null || responseData['secure_url'] == null) {
          throw Exception('Invalid response from Cloudinary - missing secure_url');
        }

        final secureUrl = responseData['secure_url'];
        
        debugPrint('File uploaded to Cloudinary: $secureUrl');
        debugPrint('Saving metadata to Firestore...');

        await FirebaseFirestore.instance.collection('modules').add({
          'fileName': fileName,
          'fileType': fileType,
          'fileSize': fileSize,
          'userId': user.uid,
          'downloadUrl': secureUrl,
          'cloudinaryPublicId': responseData['public_id'],
          'timestamp': FieldValue.serverTimestamp(),
          'subject': null,
        });

        debugPrint('Upload completed successfully!');
        
        if (mounted) {
          _showSnackBar('✅ $fileName uploaded successfully!', Colors.green);
        }
      } else {
        throw Exception('Cloudinary upload failed with status: ${response.statusCode}');
      }
    } on DioException catch (e) {
      String errorMessage;
      debugPrint('DioException: ${e.type} - ${e.message}');
      
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          errorMessage = 'Upload timeout. Please check your internet connection and try again.';
          break;
        case DioExceptionType.connectionError:
          errorMessage = 'Connection error. Please check your internet connection.';
          break;
        case DioExceptionType.badResponse:
          final statusCode = e.response?.statusCode;
          if (statusCode == 401) {
            errorMessage = 'Authentication failed. Please check Cloudinary credentials.';
          } else if (statusCode == 413) {
            errorMessage = 'File too large for upload.';
          } else {
            errorMessage = 'Server error (${statusCode}). Please try again.';
          }
          break;
        default:
          errorMessage = 'Network error: ${e.message}';
      }
      
      if (mounted) {
        _showSnackBar('❌ Upload failed: $errorMessage', Colors.red);
      }
    } on FirebaseException catch (e) {
      debugPrint('Firebase error: ${e.code} - ${e.message}');
      if (mounted) {
        _showSnackBar('❌ Database error: ${e.message}', Colors.red);
      }
    } catch (e) {
      debugPrint('Unexpected error: $e');
      if (mounted) {
        _showSnackBar('❌ Unexpected error: ${e.toString()}', Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadProgress = 0.0;
        });
      }
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              backgroundColor == Colors.green ? Icons.check_circle : 
              backgroundColor == Colors.red ? Icons.error : Icons.info,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: Duration(seconds: backgroundColor == Colors.green ? 3 : 5),
      ),
    );
  }

  // REPLACE THE EXISTING _openFile METHOD WITH THIS NEW ONE
  void _openFile(String url, String fileName, String fileType) {
    // Use the new web-compatible document viewer
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => kIsWeb 
            ? WebDocumentViewer( // Make sure to import this class
                url: url,
                fileName: fileName,
                fileType: fileType,
              )
            : WebViewScreen( // Keep original for mobile platforms
                url: url,
                fileName: fileName,
                fileType: fileType,
              ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: animation.drive(
              Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
                  .chain(CurveTween(curve: Curves.easeInOut)),
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final colorScheme = Theme.of(context).colorScheme;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.surface,
              colorScheme.surface.withOpacity(0.8),
            ],
          ),
        ),
        child: Column(
          children: [
            // Header Section
            Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF5722), Color(0xFFFF8A65)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepOrange.withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.cloud_upload_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Upload Your Files',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Share your documents with ease',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // Upload Button
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _uploading ? 1.0 : 1.0 + (_pulseController.value * 0.05),
                        child: Container(
                          width: double.infinity,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _uploading ? null : _pickAndUploadFile,
                              borderRadius: BorderRadius.circular(16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_rounded,
                                    color: _uploading ? Colors.grey : Colors.deepOrange,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _uploading ? 'Uploading...' : 'Choose File',
                                    style: TextStyle(
                                      color: _uploading ? Colors.grey : Colors.deepOrange,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Supported: PPTX • DOCX • Max 50MB',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Upload Progress
            if (_uploading)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.deepOrange.withOpacity(0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.deepOrange.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.deepOrange),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Uploading... ${(_uploadProgress * 100).toInt()}%',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Please wait while your file is being processed',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _uploadProgress,
                        backgroundColor: Colors.grey[200],
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.deepOrange),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              ),

            // Files List
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: user != null 
                    ? FirebaseFirestore.instance
                        .collection('modules')
                        .where('userId', isEqualTo: user.uid)
                        .snapshots()
                    : null,
                builder: (context, snapshot) {
                  if (user == null) {
                    return _buildEmptyState(
                      icon: Icons.login_rounded,
                      title: 'Please Log In',
                      subtitle: 'Sign in to view and upload your files',
                    );
                  }

                  if (snapshot.hasError) {
                    debugPrint('StreamBuilder error: ${snapshot.error}');
                    return _buildEmptyState(
                      icon: Icons.error_outline_rounded,
                      title: 'Error Loading Files',
                      subtitle: 'Please try again later',
                    );
                  }
                  
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.deepOrange),
                      ),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return _buildEmptyState(
                      icon: Icons.folder_open_rounded,
                      title: 'No Files Yet',
                      subtitle: 'Upload your first PPTX or DOCX file to get started',
                    );
                  }

                  final docs = snapshot.data!.docs;
                  
                  // Sort documents by timestamp
                  docs.sort((a, b) {
                    final aData = a.data() as Map<String, dynamic>;
                    final bData = b.data() as Map<String, dynamic>;
                    final aTimestamp = aData['timestamp'] as Timestamp?;
                    final bTimestamp = bData['timestamp'] as Timestamp?;
                    
                    if (aTimestamp == null && bTimestamp == null) return 0;
                    if (aTimestamp == null) return 1;
                    if (bTimestamp == null) return -1;
                    
                    return bTimestamp.compareTo(aTimestamp);
                  });

                  return ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final downloadUrl = data['downloadUrl'] as String? ?? '';
                      final fileName = data['fileName'] as String? ?? 'Unknown file';
                      final fileType = data['fileType'] as String? ?? 'unknown';
                      final fileSize = data['fileSize'] as int? ?? 0;

                      return AnimatedContainer(
                        duration: Duration(milliseconds: 300 + (index * 100)),
                        curve: Curves.easeOutBack,
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Container(
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(
                              color: Colors.grey.withOpacity(0.1),
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: downloadUrl.isNotEmpty 
                                  ? () => _openFile(downloadUrl, fileName, fileType)
                                  : null,
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    // File Icon
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: _getFileColors(fileType),
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        _getFileIcon(fileType),
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                    
                                    const SizedBox(width: 16),
                                    
                                    // File Info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            fileName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 16,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: _getFileColors(fileType)[0].withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  fileType.toUpperCase(),
                                                  style: TextStyle(
                                                    color: _getFileColors(fileType)[0],
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                '${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB',
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    
                                    // Action Buttons
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _buildActionButton(
                                          icon: Icons.visibility_rounded,
                                          onPressed: downloadUrl.isNotEmpty 
                                              ? () => _openFile(downloadUrl, fileName, fileType)
                                              : null,
                                          color: Colors.blue,
                                        ),
                                        const SizedBox(width: 8),
                                        _buildActionButton(
                                          icon: Icons.download_rounded,
                                          onPressed: downloadUrl.isNotEmpty 
                                              ? () => _launchUrl(downloadUrl)
                                              : null,
                                          color: Colors.green,
                                        ),
                                        const SizedBox(width: 8),
                                        _buildActionButton(
                                          icon: Icons.delete_rounded,
                                          onPressed: () => _deleteFile(
                                            doc.id, 
                                            data['cloudinaryPublicId'] as String? ?? '', 
                                            fileName
                                          ),
                                          color: Colors.red,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              size: 40,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required Color color,
  }) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Icon(
            icon,
            size: 18,
            color: color,
          ),
        ),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          _showSnackBar('Could not launch URL', Colors.red);
        }
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
      if (mounted) {
        _showSnackBar('Error opening file', Colors.red);
      }
    }
  }
 Future<void> _deleteFile(String docId, String cloudinaryPublicId, String fileName) async {
  try {
    // Show confirmation dialog
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete File'),
          content: Text('Are you sure you want to delete "$fileName"? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    _showSnackBar('Deleting $fileName...', Colors.orange);

    // Delete from Cloudinary
    final dio = Dio();
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final params = {
      'public_id': cloudinaryPublicId,
      'timestamp': timestamp.toString(),
    };

    final signature = await _generateSignature(params);

    final deleteUrl = 'https://api.cloudinary.com/v1_1/$cloudinaryCloudName/image/destroy';
    
    final response = await dio.post(
      deleteUrl,
      data: {
        'public_id': cloudinaryPublicId,
        'timestamp': timestamp.toString(),
        'api_key': cloudinaryApiKey,
        'signature': signature,
      },
      options: Options(
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      ),
    );

    debugPrint('Cloudinary delete response: ${response.data}');

    // Delete from Firestore
    await FirebaseFirestore.instance.collection('modules').doc(docId).delete();

    if (mounted) {
      _showSnackBar('✅ $fileName deleted successfully!', Colors.green);
    }

  } catch (e) {
    debugPrint('Error deleting file: $e');
    if (mounted) {
      _showSnackBar('❌ Error deleting file: ${e.toString()}', Colors.red);
    }
  }
}

  IconData _getFileIcon(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'docx':
        return Icons.description_rounded;
      case 'pptx':
        return Icons.slideshow_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  List<Color> _getFileColors(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'docx':
        return [const Color(0xFF2196F3), const Color(0xFF64B5F6)];
      case 'pptx':
        return [const Color(0xFFFF5722), const Color(0xFFFF8A65)];
      default:
        return [const Color(0xFF757575), const Color(0xFFBDBDBD)];
    }
  }
}