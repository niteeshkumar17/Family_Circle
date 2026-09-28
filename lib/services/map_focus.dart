import 'dart:async';

/// Lets any tab ask the home map to open a member.
///
/// The home map stays alive in the home screen's IndexedStack, so focusing it
/// is instant, whereas pushing a screen with its own GoogleMap costs a few
/// seconds of native map start-up on Android before anything is drawn.
class MapFocus {
  MapFocus._();

  static final _requests = StreamController<String>.broadcast();

  static Stream<String> get requests => _requests.stream;

  static void showMember(String memberId) => _requests.add(memberId);
}
