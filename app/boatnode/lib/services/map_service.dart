import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';

class MapService {
  static final ValueNotifier<double> cachingProgress = ValueNotifier(0.0);

  static Future<void> cacheArea(
    BuildContext context,
    double lat,
    double lon,
  ) async {
    // Check for internet connection first
    bool hasInternet = await InternetConnectionChecker().hasConnection;
    if (!hasInternet) {
      print("No internet connection. Skipping map caching.");
      return;
    }

    print("Starting background map caching for location: $lat, $lon");

    final List<String> urls = [];

    // Tier 1: Wide Area (500km) - Low Zoom (8-11)
    await _cacheZoomLevels(context, lat, lon, 500.0, [8, 9, 10, 11], urls);

    // Tier 2: Local Area (50km) - Medium Zoom (12-14)
    // Caching 500km at zoom 14 would be ~250k tiles, so we restrict radius.
    await _cacheZoomLevels(context, lat, lon, 50.0, [12, 13, 14], urls);

    // Tier 3: Immediate Area (10km) - High Zoom (15-16)
    await _cacheZoomLevels(context, lat, lon, 10.0, [15, 16], urls);

    print("Queued ${urls.length} tiles for caching...");

    // 2. Download tiles in background
    // We don't await this fully in the UI thread to avoid blocking,
    // but we process it here.
    const batchSize = 20;

    int successCount = 0;
    cachingProgress.value = 0.0; // Reset progress

    for (var i = 0; i < urls.length; i += batchSize) {
      final end = (i + batchSize < urls.length) ? i + batchSize : urls.length;
      final batch = urls.sublist(i, end);

      await Future.wait(
        batch.map((url) async {
          try {
            // Use precacheImage to fetch and store in cache
            if (context.mounted) {
              await precacheImage(CachedNetworkImageProvider(url), context);
              successCount++;
            }
          } catch (e) {
            // Ignore errors for individual tiles
            // print("Failed to cache $url: $e");
          }
        }),
      );

      // Small delay to be nice to the network/thread
      // Small delay to be nice to the network/thread
      await Future.delayed(const Duration(milliseconds: 50));

      // Update progress
      cachingProgress.value = (i + batchSize) / urls.length;
    }
    cachingProgress.value = 1.0; // Ensure complete

    print(
      "Map caching completed. Cached $successCount / ${urls.length} tiles.",
    );
  }

  static Future<void> _cacheZoomLevels(
    BuildContext context,
    double lat,
    double lon,
    double radiusKm,
    List<int> zooms,
    List<String> urls,
  ) async {
    const double kmPerDegree = 111.0;
    final double deltaDeg = radiusKm / kmPerDegree;

    final double north = lat + deltaDeg;
    final double south = lat - deltaDeg;
    final double east = lon + deltaDeg;
    final double west = lon - deltaDeg;

    for (final z in zooms) {
      final n = math.pow(2, z);
      final xMin = ((west + 180) / 360 * n).floor();
      final xMax = ((east + 180) / 360 * n).floor();
      final yMin =
          ((1 -
                      (math.log(
                            math.tan(north * math.pi / 180) +
                                1 / math.cos(north * math.pi / 180),
                          ) /
                          math.pi)) /
                  2 *
                  n)
              .floor();
      final yMax =
          ((1 -
                      (math.log(
                            math.tan(south * math.pi / 180) +
                                1 / math.cos(south * math.pi / 180),
                          ) /
                          math.pi)) /
                  2 *
                  n)
              .floor();

      for (int x = xMin; x <= xMax; x++) {
        for (int y = yMin; y <= yMax; y++) {
          urls.add('https://tile.openstreetmap.org/$z/$x/$y.png');
          urls.add('https://tiles.openseamap.org/seamark/$z/$x/$y.png');
        }
      }
    }
  }
}
