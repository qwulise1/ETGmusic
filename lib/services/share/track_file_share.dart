import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:etgmusic/models/metadata/metadata.dart';
import 'package:etgmusic/provider/local_tracks/local_tracks_provider.dart';
import 'package:etgmusic/provider/server/sourced_track_provider.dart';
import 'package:etgmusic/services/dio/dio.dart';
import 'package:etgmusic/services/telegram/telegram_media.dart';
import 'package:etgmusic/utils/service_utils.dart';

class TrackFileShareService {
  static const _channel = MethodChannel("io.qwulise1.etgmusic/share");

  static Future<String> prepareShareFile(
    dynamic ref,
    SpotubeTrackObject track,
  ) async {
    if (track is SpotubeLocalTrackObject) {
      return track.path;
    }

    final localPath = await _findLocalCopy(ref, track);
    if (localPath != null) return localPath;

    if (track is! SpotubeFullTrackObject) {
      throw FileSystemException("Track can't be shared as a file");
    }

    final telegramFile = await _resolveTelegramFile(ref, track);
    if (telegramFile != null) return telegramFile;

    final sourcedTrack = await ref.read(sourcedTrackProvider(track).future);
    final stream = sourcedTrack.getStreamOfQuality(
          sourcedTrack.qualityPreset ??
              SpotubeAudioSourceContainerPreset.lossy(
                type: SpotubeMediaCompressionType.lossy,
                name: "mp4",
                qualities: [
                  SpotubeAudioLossyContainerQuality(bitrate: 128000),
                ],
              ),
          0,
        ) ??
        sourcedTrack.sources.firstOrNull;
    final url = stream?.url ?? sourcedTrack.url;
    if (url == null || url.trim().isEmpty) {
      throw FileSystemException("No playable stream for sharing");
    }

    final extension = _extensionFor(
      url: url,
      container: stream?.container,
    );
    final target = await _shareCacheFile(track, extension);
    if (await target.exists() && await target.length() > 0) {
      return target.path;
    }

    await target.create(recursive: true);
    await globalDio.download(
      url,
      target.path,
      deleteOnError: true,
    );
    return target.path;
  }

  static Future<bool> shareTrack(dynamic ref, SpotubeTrackObject track) async {
    final path = await prepareShareFile(ref, track);
    final mimeType = lookupMimeType(path) ?? "audio/*";
    final title = "${track.name} - ${track.artists.asString()}";

    if (Platform.isAndroid) {
      final result = await _channel.invokeMethod<bool>(
        "shareFile",
        {
          "path": path,
          "mimeType": mimeType,
          "title": title,
        },
      );
      return result == true;
    }

    throw UnsupportedError("File sharing is implemented for Android");
  }

  static Future<String?> _findLocalCopy(
    dynamic ref,
    SpotubeTrackObject track,
  ) async {
    final localTracks = await ref.read(localTracksProvider.future);
    final local = localTracks.values.expand((tracks) => tracks).firstWhereOrNull(
          (item) =>
              item.name == track.name &&
              item.album.name == track.album.name &&
              item.artists.asString() == track.artists.asString(),
        );
    if (local == null) return null;
    final file = File(local.path);
    if (await file.exists() && await file.length() > 0) {
      return file.path;
    }
    return null;
  }

  static Future<String?> _resolveTelegramFile(
    dynamic ref,
    SpotubeFullTrackObject track,
  ) async {
    if (!track.id.startsWith("telegram:")) return null;

    final playableUrl = await ref
        .read(telegramMediaServiceProvider)
        .resolvePlayableUrl(track.id);
    final uri = Uri.tryParse(playableUrl);
    if (uri?.scheme == "file") {
      final path = uri!.toFilePath();
      final file = File(path);
      if (await file.exists() && await file.length() > 0) {
        return path;
      }
    }

    if (playableUrl.startsWith("http://") || playableUrl.startsWith("https://")) {
      final target = await _shareCacheFile(
        track,
        _extensionFor(url: playableUrl),
      );
      if (await target.exists() && await target.length() > 0) {
        return target.path;
      }
      await target.create(recursive: true);
      await globalDio.download(
        playableUrl,
        target.path,
        deleteOnError: true,
      );
      return target.path;
    }

    return null;
  }

  static Future<File> _shareCacheFile(
    SpotubeTrackObject track,
    String extension,
  ) async {
    final dir = Directory(
      p.join((await getTemporaryDirectory()).path, "etgmusic", "share"),
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final fileName = ServiceUtils.sanitizeFilename(
      "${track.name} - ${track.artists.asString()}.$extension",
    );
    return File(p.join(dir.path, fileName));
  }

  static String _extensionFor({
    required String url,
    String? container,
  }) {
    final normalizedContainer = container?.trim().toLowerCase();
    if (normalizedContainer == "mp4") return "m4a";
    if (normalizedContainer == "webm") return "weba";
    if (normalizedContainer != null && normalizedContainer.isNotEmpty) {
      return normalizedContainer;
    }

    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    final extension = p.extension(path).replaceFirst(".", "");
    if (extension.isNotEmpty && extension.length <= 5) {
      return extension == "mp4" ? "m4a" : extension;
    }
    return "m4a";
  }
}
