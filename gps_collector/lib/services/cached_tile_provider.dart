import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'tile_cache_service.dart';

/// A flutter_map TileProvider that serves tiles through our SQLite cache.
class CachedTileProvider extends TileProvider {
  final TileCacheService _cache = TileCacheService();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return CachedTileImageProvider(
      z: coordinates.z.toInt(),
      x: coordinates.x.toInt(),
      y: coordinates.y.toInt(),
      cache: _cache,
    );
  }
}

class CachedTileImageProvider extends ImageProvider<CachedTileImageProvider> {
  final int z;
  final int x;
  final int y;
  final TileCacheService cache;

  CachedTileImageProvider({
    required this.z,
    required this.x,
    required this.y,
    required this.cache,
  });

  @override
  Future<CachedTileImageProvider> obtainKey(ImageConfiguration configuration) {
    return Future.value(this);
  }

  @override
  ImageStreamCompleter loadImage(
    CachedTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadTile(decode),
      scale: 1.0,
    );
  }

  Future<ui.Codec> _loadTile(ImageDecoderCallback decode) async {
    final data = await cache.getTile(z: z, x: x, y: y);
    if (data == null || data.isEmpty) {
      throw Exception('Failed to load tile $z/$x/$y');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(data);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) {
    if (other is CachedTileImageProvider) {
      return z == other.z && x == other.x && y == other.y;
    }
    return false;
  }

  @override
  int get hashCode => Object.hash(z, x, y);
}
