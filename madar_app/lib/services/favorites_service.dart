import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Singleton — all pages share one cache so changes are instantly reflected
// everywhere without waiting for a Firestore re-fetch.
class FavoritesService {
  static final FavoritesService _instance = FavoritesService._internal();
  factory FavoritesService() => _instance;
  FavoritesService._internal();

  List<Map<String, dynamic>> _list = [];

  DocumentReference<Map<String, dynamic>> get _doc {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  Future<void> load() async {
    final snap = await _doc.get();
    final raw = snap.data()?['favoriteFriends'];
    _list = raw is List
        ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : [];
  }

  bool isFavorite(String phone) => _list.any((f) => f['phone'] == phone);

  List<Map<String, dynamic>> get all => List.from(_list);

  Future<void> toggle(String phone, String name) async {
    if (isFavorite(phone)) {
      _list.removeWhere((f) => f['phone'] == phone);
    } else {
      _list.add({'phone': phone, 'name': name});
    }
    await _doc.update({'favoriteFriends': _list});
  }
}
