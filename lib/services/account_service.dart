import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';

/// Account deletion is soft for [recoveryDays]; the schedule itself lives on
/// the server (see requestAccountDeletion in firebase/functions/index.js).
class AccountService {
  static const int recoveryDays = 30;

  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Returns when the account will be permanently erased.
  Future<DateTime> requestDeletion() async {
    final result = await _call('requestAccountDeletion');
    return DateTime.parse(result['scheduledFor'] as String).toLocal();
  }

  Future<void> cancelDeletion() => _call('cancelAccountDeletion');

  static DateTime? scheduledDeletionOf(Map<String, dynamic>? userData) {
    final value = userData?['deletionScheduledFor'];
    return value is Timestamp ? value.toDate() : null;
  }

  static String formatDate(DateTime date) => DateFormat('d MMMM yyyy').format(date);

  Future<Map<String, dynamic>> _call(String name) async {
    try {
      final result = await _functions.httpsCallable(name).call();
      return Map<String, dynamic>.from(result.data as Map? ?? const {});
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'failed-precondition':
          throw Exception(e.message ?? 'Request was rejected');
        case 'unavailable':
        case 'deadline-exceeded':
          throw Exception('No connection to the server. Check your internet and try again.');
        default:
          throw Exception('Something went wrong. Please try again.');
      }
    }
  }
}
