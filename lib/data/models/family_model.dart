import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:json_annotation/json_annotation.dart';

part 'family_model.g.dart';

@JsonSerializable(explicitToJson: true)
class FamilyModel {
  final String id;
  final String name;
  final String? photoUrl;
  final String createdBy;
  @JsonKey(fromJson: _dateTimeFromTimestamp, toJson: _dateTimeToTimestamp)
  final DateTime createdAt;
  final List<FamilyMember> members;
  final FamilySettings settings;
  final String? inviteCode;

  FamilyModel({
    required this.id,
    required this.name,
    this.photoUrl,
    required this.createdBy,
    required this.createdAt,
    this.members = const [],
    required this.settings,
    this.inviteCode,
  });

  factory FamilyModel.fromJson(Map<String, dynamic> json) =>
      _$FamilyModelFromJson(json);

  Map<String, dynamic> toJson() => _$FamilyModelToJson(this);

  factory FamilyModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FamilyModel.fromJson({...data, 'id': doc.id});
  }

  FamilyModel copyWith({
    String? id,
    String? name,
    String? photoUrl,
    String? createdBy,
    DateTime? createdAt,
    List<FamilyMember>? members,
    FamilySettings? settings,
    String? inviteCode,
  }) {
    return FamilyModel(
      id: id ?? this.id,
      name: name ?? this.name,
      photoUrl: photoUrl ?? this.photoUrl,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      members: members ?? this.members,
      settings: settings ?? this.settings,
      inviteCode: inviteCode ?? this.inviteCode,
    );
  }

  int get adminCount => members.where((m) => m.role == FamilyRole.admin).length;
  int get memberCount => members.length;

  static DateTime _dateTimeFromTimestamp(dynamic timestamp) {
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    }
    if (timestamp is int) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    return DateTime.now();
  }

  static dynamic _dateTimeToTimestamp(DateTime dateTime) {
    return Timestamp.fromDate(dateTime);
  }
}

@JsonSerializable(explicitToJson: true)
class FamilyMember {
  final String id;
  final String oderId;
  final String displayName;
  final String? photoUrl;
  @JsonKey(fromJson: _roleFromString, toJson: _roleToString)
  final FamilyRole role;
  @JsonKey(fromJson: FamilyModel._dateTimeFromTimestamp, toJson: FamilyModel._dateTimeToTimestamp)
  final DateTime joinedAt;
  final bool locationSharingEnabled;
  final MemberPermissions permissions;

  FamilyMember({
    required this.id,
    required this.oderId,
    required this.displayName,
    this.photoUrl,
    required this.role,
    required this.joinedAt,
    this.locationSharingEnabled = true,
    required this.permissions,
  });

  factory FamilyMember.fromJson(Map<String, dynamic> json) =>
      _$FamilyMemberFromJson(json);

  Map<String, dynamic> toJson() => _$FamilyMemberToJson(this);

  bool get isAdmin => role == FamilyRole.admin;

  FamilyMember copyWith({
    String? id,
    String? oderId,
    String? displayName,
    String? photoUrl,
    FamilyRole? role,
    DateTime? joinedAt,
    bool? locationSharingEnabled,
    MemberPermissions? permissions,
  }) {
    return FamilyMember(
      id: id ?? this.id,
      oderId: oderId ?? this.oderId,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      role: role ?? this.role,
      joinedAt: joinedAt ?? this.joinedAt,
      locationSharingEnabled: locationSharingEnabled ?? this.locationSharingEnabled,
      permissions: permissions ?? this.permissions,
    );
  }

  static FamilyRole _roleFromString(String role) {
    return FamilyRole.values.firstWhere(
      (e) => e.name == role,
      orElse: () => FamilyRole.member,
    );
  }

  static String _roleToString(FamilyRole role) => role.name;
}

enum FamilyRole { admin, member }

@JsonSerializable()
class MemberPermissions {
  final bool canViewLocation;
  final bool canViewHistory;
  final bool canManageGeofences;
  final bool canInviteMembers;
  final bool canRemoveMembers;

  MemberPermissions({
    this.canViewLocation = true,
    this.canViewHistory = true,
    this.canManageGeofences = false,
    this.canInviteMembers = false,
    this.canRemoveMembers = false,
  });

  factory MemberPermissions.fromJson(Map<String, dynamic> json) =>
      _$MemberPermissionsFromJson(json);

  Map<String, dynamic> toJson() => _$MemberPermissionsToJson(this);

  factory MemberPermissions.admin() => MemberPermissions(
        canViewLocation: true,
        canViewHistory: true,
        canManageGeofences: true,
        canInviteMembers: true,
        canRemoveMembers: true,
      );

  factory MemberPermissions.member() => MemberPermissions(
        canViewLocation: true,
        canViewHistory: true,
        canManageGeofences: false,
        canInviteMembers: false,
        canRemoveMembers: false,
      );

  MemberPermissions copyWith({
    bool? canViewLocation,
    bool? canViewHistory,
    bool? canManageGeofences,
    bool? canInviteMembers,
    bool? canRemoveMembers,
  }) {
    return MemberPermissions(
      canViewLocation: canViewLocation ?? this.canViewLocation,
      canViewHistory: canViewHistory ?? this.canViewHistory,
      canManageGeofences: canManageGeofences ?? this.canManageGeofences,
      canInviteMembers: canInviteMembers ?? this.canInviteMembers,
      canRemoveMembers: canRemoveMembers ?? this.canRemoveMembers,
    );
  }
}

@JsonSerializable()
class FamilySettings {
  final int maxMembers;
  final bool requireAdminApproval;
  final int locationHistoryDays;
  final bool premiumEnabled;

  FamilySettings({
    this.maxMembers = 5,
    this.requireAdminApproval = false,
    this.locationHistoryDays = 7,
    this.premiumEnabled = false,
  });

  factory FamilySettings.fromJson(Map<String, dynamic> json) =>
      _$FamilySettingsFromJson(json);

  Map<String, dynamic> toJson() => _$FamilySettingsToJson(this);

  factory FamilySettings.free() => FamilySettings(
        maxMembers: 5,
        locationHistoryDays: 7,
        premiumEnabled: false,
      );

  factory FamilySettings.premium() => FamilySettings(
        maxMembers: 20,
        locationHistoryDays: 30,
        premiumEnabled: true,
      );

  FamilySettings copyWith({
    int? maxMembers,
    bool? requireAdminApproval,
    int? locationHistoryDays,
    bool? premiumEnabled,
  }) {
    return FamilySettings(
      maxMembers: maxMembers ?? this.maxMembers,
      requireAdminApproval: requireAdminApproval ?? this.requireAdminApproval,
      locationHistoryDays: locationHistoryDays ?? this.locationHistoryDays,
      premiumEnabled: premiumEnabled ?? this.premiumEnabled,
    );
  }
}
