import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'database_service.dart';

enum TrackingState { idle, recording, paused }

class TrackingService {
  final DatabaseService _db = DatabaseService();

  TrackingState _state = TrackingState.idle;
  TrackingState get state => _state;

  int? _activeTrackId;
  int? get activeTrackId => _activeTrackId;

  int _pointCount = 0;
  int get pointCount => _pointCount;

  DateTime? _startTime;

  StreamSubscription<Position>? _positionSubscription;

  /// Called whenever a new GPS point is recorded.
  void Function(Position position)? onPositionUpdate;

  /// Start recording a new track.
  Future<void> startRecording() async {
    if (_state == TrackingState.recording) {
      return;
    }

    _startTime = DateTime.now().toUtc();
    final trackName = 'Track ${DateTime.now().toString().substring(0, 16)}';

    _activeTrackId = await _db.createTrack(
      name: trackName,
      startedAt: _startTime!.toIso8601String(),
    );
    _pointCount = 0;
    _state = TrackingState.recording;

    _startListening();
  }

  int _msSinceStart() {
    return DateTime.now().toUtc().difference(_startTime!).inMilliseconds;
  }

  /// Pause GPS collection (keeps track open).
  Future<void> pause() async {
    if (_state != TrackingState.recording || _activeTrackId == null) {
      return;
    }
    await _db.insertPauseEvent(
      trackId: _activeTrackId!,
      msSinceStart: _msSinceStart(),
    );
    _state = TrackingState.paused;
    _positionSubscription?.pause();
  }

  /// Resume GPS collection after pause.
  Future<void> resume() async {
    if (_state != TrackingState.paused || _activeTrackId == null) {
      return;
    }
    await _db.insertUnpauseEvent(
      trackId: _activeTrackId!,
      msSinceStart: _msSinceStart(),
    );
    _state = TrackingState.recording;
    _positionSubscription?.resume();
  }

  /// Stop recording and finalize the track.
  Future<void> stop() async {
    if (_state == TrackingState.idle) {
      return;
    }

    await _positionSubscription?.cancel();
    _positionSubscription = null;

    if (_activeTrackId != null) {
      final now = DateTime.now().toUtc().toIso8601String();
      await _db.finalizeTrack(
        trackId: _activeTrackId!,
        endedAt: now,
      );
    }

    _state = TrackingState.idle;
    _activeTrackId = null;
    _startTime = null;
    _pointCount = 0;
  }

  void _startListening() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // metres between updates
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(_onPosition);
  }

  Future<void> _onPosition(Position position) async {
    if (_activeTrackId == null || _startTime == null) {
      return;
    }

    final msSinceStart = position.timestamp
        .toUtc()
        .difference(_startTime!)
        .inMilliseconds;

    await _db.insertTrackPoint(
      trackId: _activeTrackId!,
      latitude: position.latitude,
      longitude: position.longitude,
      msSinceStart: msSinceStart,
      accuracyMeters: position.accuracy,
    );

    _pointCount++;
    onPositionUpdate?.call(position);
  }

  void dispose() {
    _positionSubscription?.cancel();
  }
}
