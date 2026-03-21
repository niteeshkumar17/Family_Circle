import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../data/models/location_model.dart';
import '../../../services/location_service.dart';

// Events
abstract class LocationEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LocationStartTracking extends LocationEvent {}

class LocationStopTracking extends LocationEvent {}

class LocationUpdated extends LocationEvent {
  final LocationModel location;
  LocationUpdated(this.location);
  @override
  List<Object?> get props => [location];
}

class FamilyLocationsUpdated extends LocationEvent {
  final Map<String, LocationModel> locations;
  FamilyLocationsUpdated(this.locations);
  @override
  List<Object?> get props => [locations];
}

class LocationRefreshRequested extends LocationEvent {}

// States
abstract class LocationState extends Equatable {
  @override
  List<Object?> get props => [];
}

class LocationInitial extends LocationState {}

class LocationLoading extends LocationState {}

class LocationActive extends LocationState {
  final LocationModel? currentLocation;
  final Map<String, LocationModel> familyLocations;
  final bool isTracking;

  LocationActive({
    this.currentLocation,
    this.familyLocations = const {},
    this.isTracking = false,
  });

  @override
  List<Object?> get props => [currentLocation, familyLocations, isTracking];

  LocationActive copyWith({
    LocationModel? currentLocation,
    Map<String, LocationModel>? familyLocations,
    bool? isTracking,
  }) {
    return LocationActive(
      currentLocation: currentLocation ?? this.currentLocation,
      familyLocations: familyLocations ?? this.familyLocations,
      isTracking: isTracking ?? this.isTracking,
    );
  }
}

class LocationError extends LocationState {
  final String message;
  LocationError(this.message);
  @override
  List<Object?> get props => [message];
}

// BLoC
class LocationBloc extends Bloc<LocationEvent, LocationState> {
  final LocationService _locationService = LocationService();
  StreamSubscription? _locationSubscription;
  StreamSubscription? _familyLocationSubscription;

  LocationBloc() : super(LocationInitial()) {
    on<LocationStartTracking>(_onStartTracking);
    on<LocationStopTracking>(_onStopTracking);
    on<LocationUpdated>(_onLocationUpdated);
    on<FamilyLocationsUpdated>(_onFamilyLocationsUpdated);
    on<LocationRefreshRequested>(_onRefreshRequested);
  }

  Future<void> _onStartTracking(
    LocationStartTracking event,
    Emitter<LocationState> emit,
  ) async {
    emit(LocationLoading());
    
    try {
      // Start tracking
      await _locationService.startTracking();
      
      // Listen to location updates
      _locationSubscription = _locationService.locationStream.listen(
        (location) => add(LocationUpdated(location)),
      );
      
      // Listen to family locations
      _familyLocationSubscription = _locationService.listenToFamilyLocations().listen(
        (locations) => add(FamilyLocationsUpdated(locations)),
      );
      
      emit(LocationActive(isTracking: true));
    } catch (e) {
      emit(LocationError(e.toString()));
    }
  }

  Future<void> _onStopTracking(
    LocationStopTracking event,
    Emitter<LocationState> emit,
  ) async {
    _locationSubscription?.cancel();
    _familyLocationSubscription?.cancel();
    _locationService.stopTracking();
    
    final currentState = state;
    if (currentState is LocationActive) {
      emit(currentState.copyWith(isTracking: false));
    }
  }

  void _onLocationUpdated(
    LocationUpdated event,
    Emitter<LocationState> emit,
  ) {
    final currentState = state;
    if (currentState is LocationActive) {
      emit(currentState.copyWith(currentLocation: event.location));
    } else {
      emit(LocationActive(currentLocation: event.location, isTracking: true));
    }
  }

  void _onFamilyLocationsUpdated(
    FamilyLocationsUpdated event,
    Emitter<LocationState> emit,
  ) {
    final currentState = state;
    if (currentState is LocationActive) {
      emit(currentState.copyWith(familyLocations: event.locations));
    } else {
      emit(LocationActive(familyLocations: event.locations));
    }
  }

  Future<void> _onRefreshRequested(
    LocationRefreshRequested event,
    Emitter<LocationState> emit,
  ) async {
    try {
      final location = await _locationService.getCurrentLocation();
      final currentState = state;
      if (currentState is LocationActive) {
        emit(currentState.copyWith(currentLocation: location));
      }
    } catch (e) {
      // Silently fail refresh
    }
  }

  @override
  Future<void> close() {
    _locationSubscription?.cancel();
    _familyLocationSubscription?.cancel();
    _locationService.dispose();
    return super.close();
  }
}
