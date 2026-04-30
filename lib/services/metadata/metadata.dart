import 'dart:typed_data';

import 'package:auto_route/auto_route.dart';
import 'package:hetu_otp_util/hetu_otp_util.dart';
import 'package:hetu_script/hetu_script.dart';
import 'package:hetu_spotube_plugin/hetu_spotube_plugin.dart' as spotube_plugin;
import 'package:hetu_spotube_plugin/hetu_spotube_plugin.dart'
    hide YouTubeEngine;
import 'package:hetu_std/hetu_std.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:etgmusic/collections/routes.dart';
import 'package:etgmusic/collections/routes.gr.dart';
import 'package:etgmusic/components/titlebar/titlebar.dart';
import 'package:etgmusic/models/metadata/metadata.dart';
import 'package:etgmusic/services/metadata/apis/localstorage.dart';
import 'package:etgmusic/services/metadata/endpoints/album.dart';
import 'package:etgmusic/services/metadata/endpoints/artist.dart';
import 'package:etgmusic/services/metadata/endpoints/audio_source.dart';
import 'package:etgmusic/services/metadata/endpoints/auth.dart';
import 'package:etgmusic/services/metadata/endpoints/browse.dart';
import 'package:etgmusic/services/metadata/endpoints/playlist.dart';
import 'package:etgmusic/services/metadata/endpoints/search.dart';
import 'package:etgmusic/services/metadata/endpoints/track.dart';
import 'package:etgmusic/services/metadata/endpoints/core.dart';
import 'package:etgmusic/services/metadata/endpoints/user.dart';
import 'package:etgmusic/services/youtube_engine/youtube_engine.dart';

const defaultMetadataLimit = "20";

class MetadataPlugin {
  static final pluginApiVersion = Version.parse("2.0.0");

  static Future<MetadataPlugin> create(
    YouTubeEngine youtubeEngine,
    PluginConfiguration config,
    Uint8List byteCode,
  ) async {
    final sharedPreferences = await SharedPreferences.getInstance();
    BuildContext? pageContext;

    final hetu = Hetu();
    hetu.init();

    HetuStdLoader.loadBindings(hetu);
    HetuSpotubePluginLoader.loadBindings(
      hetu,
      localStorageImpl: SharedPreferencesLocalStorage(
        sharedPreferences,
        config.slug,
      ),
      onNavigatorPush: (route) {
        return rootNavigatorKey.currentContext?.router
            .pushWidget(Builder(builder: (context) {
          pageContext = context;
          return Scaffold(
            headers: const [
              TitleBar(
                automaticallyImplyLeading: true,
              )
            ],
            child: route,
          );
        }));
      },
      onNavigatorPop: () {
        pageContext?.maybePop();
      },
      onShowForm: (title, fields) async {
        if (rootNavigatorKey.currentContext == null) {
          return [];
        }

        return await rootNavigatorKey.currentContext!.router
            .push<List<Map<String, dynamic>>?>(
          SettingsMetadataProviderFormRoute(
            title: title,
            fields:
                fields.map((e) => MetadataFormFieldObject.fromJson(e)).toList(),
          ),
        );
      },
      createYoutubeEngine: () {
        return spotube_plugin.YouTubeEngine(
          search: (query) async {
            final result = await youtubeEngine.searchVideos(query);
            return result
                .map((video) => {
                      'id': video.id.value,
                      'title': video.title,
                      'author': video.author,
                      'duration': video.duration?.inSeconds,
                      'description': video.description,
                      'uploadDate': video.uploadDate?.toIso8601String(),
                      'viewCount': video.engagement.viewCount,
                      'likeCount': video.engagement.likeCount,
                      'isLive': video.isLive,
                    })
                .toList();
          },
          getVideo: (videoId) async {
            final video = await youtubeEngine.getVideo(videoId);
            return {
              'id': video.id.value,
              'title': video.title,
              'author': video.author,
              'duration': video.duration?.inSeconds,
              'description': video.description,
              'uploadDate': video.uploadDate?.toIso8601String(),
              'viewCount': video.engagement.viewCount,
              'likeCount': video.engagement.likeCount,
              'isLive': video.isLive,
            };
          },
          streamManifest: (videoId) {
            return youtubeEngine.getStreamManifest(videoId).then(
              (manifest) {
                final streams = manifest.audioOnly
                    .map(
                      (stream) => {
                        'url': stream.url.toString(),
                        'quality': stream.qualityLabel,
                        'bitrate': stream.bitrate.bitsPerSecond,
                        'container': stream.container.name,
                        'videoId': stream.videoId,
                      },
                    )
                    .toList();
                return streams;
              },
            );
          },
        );
      },
    );

    await HetuStdLoader.loadBytecodeFlutter(hetu);
    await HetuOtpUtilLoader.loadBytecodeFlutter(hetu);
    await HetuSpotubePluginLoader.loadBytecodeFlutter(hetu);

    hetu.loadBytecode(bytes: byteCode, moduleName: "plugin");
    hetu.eval("""
      import "module:plugin" as plugin

      var Plugin = plugin.${config.entryPoint}

      var metadataPlugin = Plugin()
      """);

    return MetadataPlugin._(hetu);
  }

  final Hetu? hetu;

  final dynamic auth;
  final dynamic audioSource;
  final dynamic album;
  final dynamic artist;
  final dynamic browse;
  final dynamic search;
  final dynamic playlist;
  final dynamic track;
  final dynamic user;
  final dynamic core;

  MetadataPlugin.native({
    required this.auth,
    required this.audioSource,
    required this.album,
    required this.artist,
    required this.browse,
    required this.search,
    required this.playlist,
    required this.track,
    required this.user,
    required this.core,
  }) : hetu = null;

  MetadataPlugin._(Hetu value)
      : hetu = value,
        auth = MetadataAuthEndpoint(value),
        audioSource = MetadataPluginAudioSourceEndpoint(value),
        artist = MetadataPluginArtistEndpoint(value),
        album = MetadataPluginAlbumEndpoint(value),
        browse = MetadataPluginBrowseEndpoint(value),
        search = MetadataPluginSearchEndpoint(value),
        playlist = MetadataPluginPlaylistEndpoint(value),
        track = MetadataPluginTrackEndpoint(value),
        user = MetadataPluginUserEndpoint(value),
        core = MetadataPluginCore(value);
}
