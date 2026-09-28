import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/background_service.dart';
import '../../../services/family_service.dart';
import '../../../services/location_cache_service.dart';
import '../../../services/location_service.dart';
import '../../../services/notification_service.dart';
// Events
abstract class AuthEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthCheckRequested extends AuthEvent {}

class AuthGoogleSignInRequested extends AuthEvent {}

class AuthLogoutRequested extends AuthEvent {}

// States
abstract class AuthState extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final User user;
  final bool isNewUser;
  AuthAuthenticated({required this.user, this.isNewUser = false});
  @override
  List<Object?> get props => [user, isNewUser];
}

class AuthUnauthenticated extends AuthState {}

class AuthError extends AuthState {
  final String message;
  AuthError(this.message);
  @override
  List<Object?> get props => [message];
}

// BLoC
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  AuthBloc() : super(AuthInitial()) {
    on<AuthCheckRequested>(_onCheckRequested);
    on<AuthGoogleSignInRequested>(_onGoogleSignIn);
    on<AuthLogoutRequested>(_onLogoutRequested);
  }

  Future<void> _onCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    final user = _auth.currentUser;
    if (user != null) {
      emit(AuthAuthenticated(user: user));
    } else {
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onGoogleSignIn(
    AuthGoogleSignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    
    try {
      // Disconnect any previous session to avoid cached Pigeon data
      try {
        await _googleSignIn.disconnect();
      } catch (_) {}

      // Trigger the Google Sign-In flow
      GoogleSignInAccount? googleUser;
      try {
        googleUser = await _googleSignIn.signIn();
      } catch (e) {
        // Workaround for PigeonUserDetails type cast bug
        // Try signInSilently as fallback
        if (e.toString().contains('PigeonUserDetails') || 
            e.toString().contains('List<Object?>')) {
          googleUser = await _googleSignIn.signInSilently();
        } else {
          rethrow;
        }
      }
      
      if (googleUser == null) {
        // User cancelled the sign-in
        emit(AuthUnauthenticated());
        return;
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the credential
      final userCredential = await _auth.signInWithCredential(credential);
      final isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;

      emit(AuthAuthenticated(
        user: userCredential.user!,
        isNewUser: isNewUser,
      ));
    } on FirebaseAuthException catch (e) {
      emit(AuthError(e.message ?? 'Authentication failed'));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    // Tear down tracking before dropping the credentials, so the final
    // presence write and the FCM token removal still authenticate.
    try {
      final bgService = BackgroundLocationService();
      await bgService.stop();
      await bgService.clearUser();
    } catch (e) {
      debugPrint('Logout: failed to stop background service: $e');
    }

    // Without these the singletons keep the previous user's Firestore and
    // Realtime Database listeners attached across the next sign-in.
    try {
      await LocationService().reset();
    } catch (e) {
      debugPrint('Logout: failed to reset location service: $e');
    }

    try {
      await FamilyService().reset();
    } catch (e) {
      debugPrint('Logout: failed to reset family service: $e');
    }

    try {
      await NotificationService().onSignOut();
    } catch (e) {
      debugPrint('Logout: failed to clear notification state: $e');
    }

    try {
      await LocationCacheService().clearAll();
    } catch (e) {
      debugPrint('Logout: failed to clear cached locations: $e');
    }

    try {
      await _googleSignIn.disconnect();
    } catch (_) {}

    try {
      await _googleSignIn.signOut();
    } catch (_) {}

    try {
      await _auth.signOut();
    } catch (_) {}

    // Drop everything tied to the account. Onboarding and the Android
    // permission grants belong to the device, so the next sign-in should not
    // walk through them again.
    try {
      final prefs = await SharedPreferences.getInstance();
      const deviceKeys = {'onboarding_completed', 'permissions_completed'};
      final kept = {
        for (final key in deviceKeys)
          if (prefs.getBool(key) != null) key: prefs.getBool(key)!,
      };
      await prefs.clear();
      for (final entry in kept.entries) {
        await prefs.setBool(entry.key, entry.value);
      }
    } catch (_) {}

    emit(AuthUnauthenticated());
  }
}
