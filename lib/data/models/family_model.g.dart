// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'family_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FamilyModel _$FamilyModelFromJson(Map<String, dynamic> json) => FamilyModel(
      id: json['id'] as String,
      name: json['name'] as String,
      photoUrl: json['photoUrl'] as String?,
      createdBy: json['createdBy'] as String,
      createdAt: FamilyModel._dateTimeFromTimestamp(json['createdAt']),
      members: (json['members'] as List<dynamic>?)
              ?.map((e) => FamilyMember.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      settings:
          FamilySettings.fromJson(json['settings'] as Map<String, dynamic>),
      inviteCode: json['inviteCode'] as String?,
    );

Map<String, dynamic> _$FamilyModelToJson(FamilyModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'photoUrl': instance.photoUrl,
      'createdBy': instance.createdBy,
      'createdAt': FamilyModel._dateTimeToTimestamp(instance.createdAt),
      'members': instance.members.map((e) => e.toJson()).toList(),
      'settings': instance.settings.toJson(),
      'inviteCode': instance.inviteCode,
    };

FamilyMember _$FamilyMemberFromJson(Map<String, dynamic> json) => FamilyMember(
      id: json['id'] as String,
      oderId: json['oderId'] as String,
      displayName: json['displayName'] as String,
      photoUrl: json['photoUrl'] as String?,
      role: FamilyMember._roleFromString(json['role'] as String),
      joinedAt: FamilyModel._dateTimeFromTimestamp(json['joinedAt']),
      locationSharingEnabled: json['locationSharingEnabled'] as bool? ?? true,
      permissions: MemberPermissions.fromJson(
          json['permissions'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$FamilyMemberToJson(FamilyMember instance) =>
    <String, dynamic>{
      'id': instance.id,
      'oderId': instance.oderId,
      'displayName': instance.displayName,
      'photoUrl': instance.photoUrl,
      'role': FamilyMember._roleToString(instance.role),
      'joinedAt': FamilyModel._dateTimeToTimestamp(instance.joinedAt),
      'locationSharingEnabled': instance.locationSharingEnabled,
      'permissions': instance.permissions.toJson(),
    };

MemberPermissions _$MemberPermissionsFromJson(Map<String, dynamic> json) =>
    MemberPermissions(
      canViewLocation: json['canViewLocation'] as bool? ?? true,
      canViewHistory: json['canViewHistory'] as bool? ?? true,
      canManageGeofences: json['canManageGeofences'] as bool? ?? false,
      canInviteMembers: json['canInviteMembers'] as bool? ?? false,
      canRemoveMembers: json['canRemoveMembers'] as bool? ?? false,
    );

Map<String, dynamic> _$MemberPermissionsToJson(MemberPermissions instance) =>
    <String, dynamic>{
      'canViewLocation': instance.canViewLocation,
      'canViewHistory': instance.canViewHistory,
      'canManageGeofences': instance.canManageGeofences,
      'canInviteMembers': instance.canInviteMembers,
      'canRemoveMembers': instance.canRemoveMembers,
    };

FamilySettings _$FamilySettingsFromJson(Map<String, dynamic> json) =>
    FamilySettings(
      maxMembers: (json['maxMembers'] as num?)?.toInt() ?? 5,
      requireAdminApproval: json['requireAdminApproval'] as bool? ?? false,
      locationHistoryDays: (json['locationHistoryDays'] as num?)?.toInt() ?? 7,
      premiumEnabled: json['premiumEnabled'] as bool? ?? false,
    );

Map<String, dynamic> _$FamilySettingsToJson(FamilySettings instance) =>
    <String, dynamic>{
      'maxMembers': instance.maxMembers,
      'requireAdminApproval': instance.requireAdminApproval,
      'locationHistoryDays': instance.locationHistoryDays,
      'premiumEnabled': instance.premiumEnabled,
    };
