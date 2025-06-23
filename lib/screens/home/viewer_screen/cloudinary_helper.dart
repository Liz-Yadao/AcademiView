import 'dart:convert';
import 'package:crypto/crypto.dart';

class CloudinaryHelper {
  static const String cloudinaryCloudName = 'dv2wqfhvt';
  static const String cloudinaryApiKey = '282553815785198';
  static const String cloudinaryApiSecret = 'ZAbmfYUOmbs8wI7dMI2ILxl_RtE';

  /// Generate a signed URL for Cloudinary resources
  static String generateSignedUrl({
    required String publicId,
    String resourceType = 'raw',
    String type = 'upload',
    int? expiresAt,
    Map<String, dynamic>? additionalParams,
  }) {
    // Set expiration time (default: 1 hour from now)
    final timestamp = expiresAt ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600;
    
    // Build parameters for signing
    final params = <String, dynamic>{
      'timestamp': timestamp,
      'type': type,
      if (additionalParams != null) ...additionalParams,
    };
    
    // Create signature
    final signature = _createSignature(params, cloudinaryApiSecret);
    
    // Build the final URL
    final baseUrl = 'https://res.cloudinary.com/$cloudinaryCloudName';
    final resourcePath = '$resourceType/$type/$publicId';
    
    // Add query parameters
    final queryParams = <String, String>{
      'api_key': cloudinaryApiKey,
      'timestamp': timestamp.toString(),
      'signature': signature,
      if (additionalParams != null)
        ...additionalParams.map((key, value) => MapEntry(key, value.toString())),
    };
    
    final queryString = queryParams.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    
    return '$baseUrl/$resourcePath?$queryString';
  }
  
  /// Generate signed URL specifically for authenticated resources
  static String generateAuthenticatedUrl({
    required String publicId,
    String resourceType = 'raw',
    int? expiresAt,
  }) {
    return generateSignedUrl(
      publicId: publicId,
      resourceType: resourceType,
      type: 'authenticated',
      expiresAt: expiresAt,
    );
  }
  
  /// Extract public ID from Cloudinary URL
  static String? extractPublicIdFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      
      // Find the segments after 'upload' or 'authenticated'
      int startIndex = -1;
      for (int i = 0; i < pathSegments.length; i++) {
        if (pathSegments[i] == 'upload' || pathSegments[i] == 'authenticated') {
          startIndex = i + 1;
          break;
        }
      }
      
      if (startIndex == -1 || startIndex >= pathSegments.length) {
        return null;
      }
      
      // Skip version if present (starts with 'v' followed by numbers)
      if (startIndex < pathSegments.length && 
          pathSegments[startIndex].startsWith('v') && 
          pathSegments[startIndex].length > 1 &&
          int.tryParse(pathSegments[startIndex].substring(1)) != null) {
        startIndex++;
      }
      
      if (startIndex >= pathSegments.length) {
        return null;
      }
      
      // Join remaining segments and remove file extension
      String publicId = pathSegments.sublist(startIndex).join('/');
      
      // Remove file extension if present
      final lastDotIndex = publicId.lastIndexOf('.');
      if (lastDotIndex > 0) {
        publicId = publicId.substring(0, lastDotIndex);
      }
      
      return Uri.decodeComponent(publicId);
    } catch (e) {
      print('Error extracting public ID from URL: $e');
      return null;
    }
  }
  
  /// Create signature for Cloudinary API
  static String _createSignature(Map<String, dynamic> params, String apiSecret) {
    // Sort parameters by key
    final sortedKeys = params.keys.toList()..sort();
    
    // Create string to sign
    final stringToSign = sortedKeys
        .map((key) => '$key=${params[key]}')
        .join('&');
    
    // Create HMAC SHA1 signature
    final key = utf8.encode(apiSecret);
    final bytes = utf8.encode(stringToSign);
    final hmacSha1 = Hmac(sha1, key);
    final digest = hmacSha1.convert(bytes);
    
    return digest.toString();
  }
  
  /// Generate a direct download URL with authentication
  static String generateDownloadUrl({
    required String publicId,
    String resourceType = 'raw',
    String? filename,
    int? expiresAt,
  }) {
    final params = <String, dynamic>{
      'flags': 'attachment',
      if (filename != null) 'filename': filename,
    };
    
    return generateSignedUrl(
      publicId: publicId,
      resourceType: resourceType,
      type: 'authenticated',
      expiresAt: expiresAt,
      additionalParams: params,
    );
  }
}