/*import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> migrateCategories() async {
  final firestore = FirebaseFirestore.instance;

  final places = await firestore.collection('places').get();

  for (final doc in places.docs) {
    final data = doc.data();

    if (data.containsKey('category_ID') && data['category_ID'] is String) {
      final category = data['category_ID'];

      await doc.reference.update({
        'category_IDs': [category],
      });

      print('✅ Updated ${doc.id} → [$category]');
    }
  }

  print('🎉 Migration complete!');
}
*/
