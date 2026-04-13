import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/theme_config.dart';
import '../../../services/family_service.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> with TickerProviderStateMixin {
  bool _isSOSActive = false;
  bool _isConfirming = false;
  int _countdown = 3;
  late AnimationController _pulseController;
  Duration _duration = Duration.zero;
  final FamilyService _familyService = FamilyService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<FamilyMemberData> _familyMembers = [];
  StreamSubscription<List<FamilyMemberData>>? _familyMembersSubscription;
  Timer? _durationTimer;
  String? _activeSosEventId;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _loadFamilyMembers();
  }

  Future<void> _loadFamilyMembers() async {
    final familyId = await _familyService.getCurrentUserFamilyId();
    if (familyId != null) {
      await _familyMembersSubscription?.cancel();
      _familyMembersSubscription =
          _familyService.getFamilyMembersStream(familyId).listen((members) {
        if (mounted) {
          setState(() {
            _familyMembers = members;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _familyMembersSubscription?.cancel();
    _durationTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    setState(() {
      _isConfirming = true;
      _countdown = 3;
    });

    // Haptic feedback
    HapticFeedback.heavyImpact();

    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted || !_isConfirming) return;
      setState(() => _countdown = 2);
      HapticFeedback.mediumImpact();
      
      Future.delayed(const Duration(seconds: 1), () {
        if (!mounted || !_isConfirming) return;
        setState(() => _countdown = 1);
        HapticFeedback.mediumImpact();
        
        Future.delayed(const Duration(seconds: 1), () {
          if (!mounted || !_isConfirming) return;
          unawaited(_triggerSOS());
        });
      });
    });
  }

  void _cancelCountdown() {
    setState(() {
      _isConfirming = false;
      _countdown = 3;
    });
  }

  Future<void> _triggerSOS() async {
    HapticFeedback.heavyImpact();
    setState(() {
      _isConfirming = false;
      _isSOSActive = true;
    });

    // Start duration timer
    _startDurationTimer();

    // Send SOS notification to all family members
    await _sendSOSToFamily();
  }

  Future<void> _sendSOSToFamily() async {
    final familyId = await _familyService.getCurrentUserFamilyId();
    final userId = _familyService.currentUserId;

    if (familyId == null || userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to send SOS: missing family or user')),
        );
      }
      return;
    }

    FamilyMemberData? currentMember;
    for (final member in _familyMembers) {
      if (member.id == userId) {
        currentMember = member;
        break;
      }
    }

    final payload = <String, dynamic>{
      'familyId': familyId,
      'userId': userId,
      'userName': _familyService.currentUserName ?? 'A family member',
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'active',
    };

    if (currentMember?.latitude != null && currentMember?.longitude != null) {
      payload['triggerLocation'] = {
        'latitude': currentMember!.latitude,
        'longitude': currentMember.longitude,
      };
    }

    try {
      final eventRef = await _firestore.collection('sos_events').add(payload);
      _activeSosEventId = eventRef.id;
    } catch (e) {
      debugPrint('Failed to create SOS event: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to notify family. Please call emergency services.')),
        );
      }
    }
  }

  Future<void> _callEmergency() async {
    final Uri phoneUri = Uri(scheme: 'tel', path: '112'); // Emergency number (112 for most countries, 911 for US)
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch phone dialer')),
        );
      }
    }
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_isSOSActive) {
        timer.cancel();
        return;
      }

      setState(() {
        _duration += const Duration(seconds: 1);
      });
    });
  }

  Future<void> _closeActiveSosEvent() async {
    final eventId = _activeSosEventId;
    if (eventId == null) return;

    try {
      await _firestore.collection('sos_events').doc(eventId).update({
        'status': 'cancelled',
        'resolvedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Failed to close SOS event: $e');
    } finally {
      _activeSosEventId = null;
    }
  }

  void _cancelSOS() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel SOS?'),
        content: const Text('Are you sure you want to cancel the SOS alert?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No, Keep Active'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isSOSActive = false;
                _duration = Duration.zero;
              });
              _durationTimer?.cancel();
              unawaited(_closeActiveSosEvent());
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
            ),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (_isSOSActive) {
      return _buildActiveSOSScreen();
    }
    return _buildSOSTriggerScreen();
  }

  Widget _buildSOSTriggerScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'SOS Emergency',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            
            // SOS Button
            Center(
              child: GestureDetector(
                onLongPressStart: (_) => _startCountdown(),
                onLongPressEnd: (_) {
                  if (!_isSOSActive) _cancelCountdown();
                },
                child: SizedBox(
                  width: 300,
                  height: 300,
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // Pulse rings
                          ...List.generate(3, (index) {
                            final delay = index * 0.3;
                            final progress = (_pulseController.value + delay) % 1.0;
                            return Center(
                              child: Container(
                                width: 200 + (progress * 100),
                                height: 200 + (progress * 100),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.red.withOpacity(1 - progress),
                                    width: 2,
                                  ),
                                ),
                              ),
                            );
                          }),
                          
                          // Main button
                          Center(
                            child: Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: AppTheme.sosGradient,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withOpacity(0.5),
                                    blurRadius: 30,
                                    spreadRadius: 10,
                                  ),
                                ],
                              ),
                              child: Center(
                          child: _isConfirming
                              ? Text(
                                  '$_countdown',
                                  style: const TextStyle(
                                    fontSize: 72,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ).animate().scale(duration: 300.ms)
                              : const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.sos,
                                      size: 64,
                                      color: Colors.white,
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Hold',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 48),
            
            Text(
              _isConfirming
                  ? 'Release to cancel'
                  : 'Hold to send SOS alert',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
            
            const Spacer(flex: 2),
            
            // Emergency Call Button
            Padding(
              padding: const EdgeInsets.all(24),
              child: OutlinedButton.icon(
                onPressed: _callEmergency,
                icon: const Icon(Icons.phone, color: Colors.white),
                label: const Text(
                  'Call Emergency',
                  style: TextStyle(color: Colors.white),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSOSScreen() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFDC2626), Color(0xFF991B1B)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '🚨 EMERGENCY MODE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _formatDuration(_duration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              )
                  .animate(onPlay: (c) => c.repeat())
                  .fadeIn()
                  .then()
                  .fadeOut(delay: 500.ms)
                  .then()
                  .fadeIn(delay: 500.ms),
              
              // Map Placeholder
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 64,
                          color: Colors.red,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Sharing live location...',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'All family members have been notified',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Responses Section
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Family Responses',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_familyMembers.isEmpty)
                      const Text(
                        'No family members to notify',
                        style: TextStyle(color: Colors.grey),
                      )
                    else
                      ..._familyMembers.map((member) => _buildResponseItem(
                        member.name,
                        member.isOnline ? 'Notified' : 'Pending...',
                        member.isOnline ? Icons.check_circle : Icons.hourglass_empty,
                        member.isOnline ? Colors.green : Colors.orange,
                      )),
                  ],
                ),
              ),
              
              // Action Buttons
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _callEmergency,
                        icon: const Icon(Icons.phone),
                        label: const Text('Emergency Call'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _cancelSOS,
                        icon: const Icon(Icons.close),
                        label: const Text('Cancel SOS'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white24,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResponseItem(String name, String status, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withOpacity(0.1),
            child: Text(
              name[0],
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  status,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, color: color),
        ],
      ),
    );
  }
}
