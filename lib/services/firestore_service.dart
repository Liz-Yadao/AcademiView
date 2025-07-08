// services/firestore_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  String get uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  // User management
  Future<void> createUser({
    required String email,
    required String displayName,
    required String role,
  }) {
    return _db.collection('users').doc(uid).set({
      'email': email,
      'displayName': displayName,
      'role': role,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<DocumentSnapshot?> getUserData() {
    return _db.collection('users').doc(uid).get();
  }

  // Classroom management (Teacher)
  Future<String> createClassroom({
    required String className,
    required String section,
    required String subject,
  }) {
    return _db.collection('classrooms').add({
      'className': className,
      'section': section,
      'subject': subject,
      'teacherId': uid,
      'teacherName': FirebaseAuth.instance.currentUser?.displayName ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'enrolledStudents': [],
    }).then((doc) => doc.id);
  }

  Stream<QuerySnapshot> getTeacherClassrooms() {
    return _db
        .collection('classrooms')
        .where('teacherId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<DocumentSnapshot?> getClassroomById(String classroomId) {
    return _db.collection('classrooms').doc(classroomId).get();
  }

  // Student enrollment
  Future<void> enrollStudent(String classroomId, String studentName) async {
    // Fetch the current user's profilePicUrl
    final userDoc = await _db.collection('users').doc(uid).get();
    final profilePicUrl = userDoc.data()?['profilePicUrl'] as String?;

    // Fetch the classroom document
    final classroomDoc = await _db.collection('classrooms').doc(classroomId).get();
    if (!classroomDoc.exists) return;
    final classroomData = classroomDoc.data() as Map<String, dynamic>;
    final enrolledStudents = List<Map<String, dynamic>>.from(classroomData['enrolledStudents'] ?? []);

    // Remove any existing entry for this student
    enrolledStudents.removeWhere((student) => student['studentId'] == uid);

    // Add the new entry
    enrolledStudents.add({
      'studentId': uid,
      'studentName': studentName,
      'enrolledAt': Timestamp.now(),
      'profilePicUrl': profilePicUrl ?? '',
    });

    // Update the classroom document
    await _db.collection('classrooms').doc(classroomId).update({
      'enrolledStudents': enrolledStudents,
    });
  }

  Stream<List<QueryDocumentSnapshot>> getStudentClassrooms() {
    return _db
        .collection('classrooms')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      // Filter classrooms where the current user is enrolled
      return snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final enrolledStudents = List<Map<String, dynamic>>.from(
          data['enrolledStudents'] ?? [],
        );
        return enrolledStudents.any((student) => student['studentId'] == uid);
      }).toList();
    });
  }

  // Classroom materials (Teacher uploads)
  Future<void> addClassroomMaterial({
    required String classroomId,
    required String fileName,
    required String downloadUrl,
    required String fileType,
    required String description,
  }) {
    return _db.collection('classroom_materials').add({
      'classroomId': classroomId,
      'fileName': fileName,
      'downloadUrl': downloadUrl,
      'fileType': fileType,
      'description': description,
      'uploadedBy': uid,
      'uploadedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> getClassroomMaterials(String classroomId) {
    return _db
        .collection('classroom_materials')
        .where('classroomId', isEqualTo: classroomId)
        .orderBy('uploadedAt', descending: true)
        .snapshots();
  }

  // Delete classroom material from Firestore and Cloudinary
  Future<void> deleteMaterial({
    required String materialId,
    required String cloudinaryPublicId,
  }) async {
    // Delete from Firestore
    await _db.collection('classroom_materials').doc(materialId).delete();

    // Delete from Cloudinary
    const String cloudinaryCloudName = 'dv2wqfhvt';
    const String cloudinaryApiKey = '282553815785198';
    const String cloudinaryApiSecret = 'ZAbmfYUOmbs8wI7dMI2ILxl_RtE';
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final paramsToSign = 'public_id=$cloudinaryPublicId&timestamp=$timestamp$cloudinaryApiSecret';
    final signature = sha1.convert(utf8.encode(paramsToSign)).toString();

    final formData = FormData.fromMap({
      'public_id': cloudinaryPublicId,
      'timestamp': timestamp.toString(),
      'api_key': cloudinaryApiKey,
      'signature': signature,
    });

    final destroyUrl = 'https://api.cloudinary.com/v1_1/$cloudinaryCloudName/image/destroy';
    final dio = Dio();
    try {
      await dio.post(
        destroyUrl,
        data: formData,
        options: Options(
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
          headers: {'Content-Type': 'multipart/form-data'},
        ),
      );
    } catch (e) {
      // Optionally handle Cloudinary deletion errors
    }
  }

  // Notes CRUD (Student personal notes)
  Stream<QuerySnapshot> getNotesStream() {
    return _db
        .collection('notes')
        .where('userId', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Future<void> addNote(String title, String content) {
    return _db.collection('notes').add({
      'title': title,
      'content': content,
      'userId': uid,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateNote(String docId, String title, String content) {
    return _db.collection('notes').doc(docId).update({
      'title': title,
      'content': content,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteNote(String docId) {
    return _db.collection('notes').doc(docId).delete();
  }

  // Legacy file metadata (keeping for backward compatibility)
  Stream<QuerySnapshot> getFilesStream() {
    return _db
        .collection('modules')
        .where('userId', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Future<void> addFileMetadata({
    required String fileName,
    required String downloadUrl,
    required String fileType,
  }) {
    return _db.collection('modules').add({
      'fileName': fileName,
      'downloadUrl': downloadUrl,
      'fileType': fileType,
      'userId': uid,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
