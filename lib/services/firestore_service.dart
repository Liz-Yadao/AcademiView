// services/firestore_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String uid = FirebaseAuth.instance.currentUser!.uid;

  // Notes CRUD
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

  // File metadata
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
