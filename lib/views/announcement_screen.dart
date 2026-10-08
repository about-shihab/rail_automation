import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AnnouncementScreen extends StatelessWidget {
  final String notificationId;
  const AnnouncementScreen({super.key, required this.notificationId});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Announcement')),
    body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load this announcement.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!.data();
        if (data == null) {
          return const Center(
            child: Text('This announcement is no longer available.'),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              data['title']?.toString() ?? 'Announcement',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            SelectableText(
              data['body']?.toString() ?? '',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        );
      },
    ),
  );
}
