import 'dart:async';
import 'dart:developer' as developer;
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_android/geolocator_android.dart';
import 'database_service.dart';

enum TrackingState { idle, recording, paused }

/// A single speed data point captured during recording.
class SpeedDataPoint {
  final int msSinceStart;
  final double speedMps; // meters per second
  final double accuracyMeters;

  const SpeedDataPoint({
    required this.msSinceStart,
    required this.speedMps,
    required this.accuracyMeters,
  });
}

class TrackingService {
  final DatabaseService _db = DatabaseService();

  TrackingState _state = TrackingState.idle;
  TrackingState get state => _state;

  int? _activeTrackId;
  int? get activeTrackId => _activeTrackId;

  int _pointCount = 0;
  int get pointCount => _pointCount;

  Position? _lastPosition;
  Position? get lastPosition => _lastPosition;

  DateTime? _startTime;

  final List<SpeedDataPoint> _speedHistory = [];
  List<SpeedDataPoint> get speedHistory => List.unmodifiable(_speedHistory);

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
    _speedHistory.clear();
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
    _lastPosition = null;
    _speedHistory.clear();
  }

  void _startListening() {
    // intervalDuration tells Android to only poll GPS every 10s,
    // saving battery by keeping the hardware idle between polls.
    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
      intervalDuration: const Duration(seconds: 10),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'GPS Collector',
        notificationText: 'Recording GPS track',
        enableWakeLock: true,
      ),
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      _onPosition,
      onError: (error) {
        developer.log(
          'Position stream error: $error — will retry in 5s',
          name: 'tracking_service',
        );
        // The stream is dead after an error; cancel and retry.
        _positionSubscription?.cancel();
        _positionSubscription = null;
        if (_state == TrackingState.recording) {
          Future.delayed(const Duration(seconds: 5), () {
            if (_state == TrackingState.recording) {
              developer.log('Retrying position stream', name: 'tracking_service');
              _startListening();
            }
          });
        }
      },
    );
  }

  Future<void> _onPosition(Position position) async {
    developer.log(
      'lat=${position.latitude}, lon=${position.longitude}, '
      'accuracy=${position.accuracy}m',
      name: 'tracking_service',
    );
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
      speed: position.speed,
      altitude: position.altitude,
      speedAccuracy: position.speedAccuracy,
      altitudeAccuracy: position.altitudeAccuracy,
      headingAccuracy: position.headingAccuracy,
      isMocked: position.isMocked,
    );

    _pointCount++;
    _lastPosition = position;

    if (position.speed >= 0) {
      _speedHistory.add(SpeedDataPoint(
        msSinceStart: msSinceStart,
        speedMps: position.speed,
        accuracyMeters: position.accuracy,
      ));
    }

    onPositionUpdate?.call(position);
  }

  void dispose() {
    _positionSubscription?.cancel();
  }
}
