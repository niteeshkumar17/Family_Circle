import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../data/models/family_model.dart';
import '../../../services/family_service.dart';

// Events
abstract class FamilyEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class FamilyLoadRequested extends FamilyEvent {}

class FamilyCreateRequested extends FamilyEvent {
  final String name;
  FamilyCreateRequested(this.name);
  @override
  List<Object?> get props => [name];
}

class FamilyJoinRequested extends FamilyEvent {
  final String inviteCode;
  FamilyJoinRequested(this.inviteCode);
  @override
  List<Object?> get props => [inviteCode];
}

class FamilySwitched extends FamilyEvent {
  final String familyId;
  FamilySwitched(this.familyId);
  @override
  List<Object?> get props => [familyId];
}

class FamilyMemberRemoved extends FamilyEvent {
  final String memberId;
  FamilyMemberRemoved(this.memberId);
  @override
  List<Object?> get props => [memberId];
}

class FamilyInviteRequested extends FamilyEvent {}

// States
abstract class FamilyState extends Equatable {
  @override
  List<Object?> get props => [];
}

class FamilyInitial extends FamilyState {}

class FamilyLoading extends FamilyState {}

class FamilyLoaded extends FamilyState {
  final FamilyModel? currentFamily;
  final List<FamilyModel> families;
  
  FamilyLoaded({this.currentFamily, this.families = const []});
  
  @override
  List<Object?> get props => [currentFamily, families];
}

class FamilyEmpty extends FamilyState {}

class FamilyInviteGenerated extends FamilyState {
  final String inviteCode;
  final String inviteLink;
  
  FamilyInviteGenerated({required this.inviteCode, required this.inviteLink});
  
  @override
  List<Object?> get props => [inviteCode, inviteLink];
}

class FamilyError extends FamilyState {
  final String message;
  FamilyError(this.message);
  @override
  List<Object?> get props => [message];
}

// BLoC
class FamilyBloc extends Bloc<FamilyEvent, FamilyState> {
  final FamilyService _familyService = FamilyService();
  FamilyModel? _currentFamily;
  List<FamilyModel> _families = [];

  FamilyBloc() : super(FamilyInitial()) {
    on<FamilyLoadRequested>(_onLoadRequested);
    on<FamilyCreateRequested>(_onCreateRequested);
    on<FamilyJoinRequested>(_onJoinRequested);
    on<FamilySwitched>(_onSwitched);
  }

  Future<void> _onLoadRequested(
    FamilyLoadRequested event,
    Emitter<FamilyState> emit,
  ) async {
    emit(FamilyLoading());
    
    try {
      // Initialize family service and load current family
      await _familyService.initialize();
      final familyInfo = await _familyService.getCurrentFamilyInfo();
      
      if (familyInfo == null) {
        emit(FamilyEmpty());
      } else {
        _currentFamily = FamilyModel(
          id: familyInfo.id,
          name: familyInfo.familyName,
          createdBy: familyInfo.createdBy ?? '',
          createdAt: familyInfo.createdAt ?? DateTime.now(),
          members: [],
          settings: FamilySettings.free(),
          inviteCode: familyInfo.inviteCode,
        );
        _families = [_currentFamily!];
        emit(FamilyLoaded(
          currentFamily: _currentFamily,
          families: _families,
        ));
      }
    } catch (e) {
      emit(FamilyError(e.toString()));
    }
  }

  Future<void> _onCreateRequested(
    FamilyCreateRequested event,
    Emitter<FamilyState> emit,
  ) async {
    emit(FamilyLoading());
    
    try {
      // Create family using FamilyService
      final familyId = await _familyService.createFamily(event.name);
      final familyInfo = await _familyService.getCurrentFamilyInfo();
      
      if (familyInfo != null) {
        _currentFamily = FamilyModel(
          id: familyId,
          name: familyInfo.familyName,
          createdBy: familyInfo.createdBy ?? '',
          createdAt: familyInfo.createdAt ?? DateTime.now(),
          members: [],
          settings: FamilySettings.free(),
          inviteCode: familyInfo.inviteCode,
        );
        _families = [_currentFamily!];
      }
      
      emit(FamilyLoaded(
        currentFamily: _currentFamily,
        families: _families,
      ));
    } catch (e) {
      emit(FamilyError(e.toString()));
    }
  }

  Future<void> _onJoinRequested(
    FamilyJoinRequested event,
    Emitter<FamilyState> emit,
  ) async {
    emit(FamilyLoading());
    
    try {
      // Join family using invite code
      final success = await _familyService.joinFamily(event.inviteCode);
      
      if (success) {
        final familyInfo = await _familyService.getCurrentFamilyInfo();
        if (familyInfo != null) {
          _currentFamily = FamilyModel(
            id: familyInfo.id,
            name: familyInfo.familyName,
            createdBy: familyInfo.createdBy ?? '',
            createdAt: familyInfo.createdAt ?? DateTime.now(),
            members: [],
            settings: FamilySettings.free(),
            inviteCode: familyInfo.inviteCode,
          );
          _families = [_currentFamily!];
        }
        emit(FamilyLoaded(
          currentFamily: _currentFamily,
          families: _families,
        ));
      } else {
        emit(FamilyError('Invalid invite code'));
      }
    } catch (e) {
      emit(FamilyError(e.toString()));
    }
  }

  Future<void> _onSwitched(
    FamilySwitched event,
    Emitter<FamilyState> emit,
  ) async {
    _currentFamily = _families.firstWhere(
      (f) => f.id == event.familyId,
      orElse: () => _families.first,
    );
    
    emit(FamilyLoaded(
      currentFamily: _currentFamily,
      families: _families,
    ));
  }
}
