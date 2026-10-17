import 'package:flutter/material.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Deterministic stand-in for the native decoder in widget screenshots.
/// This colored scene is test artwork, not production video playback.
class ScreenshotVideo extends VideoPlayerPlatform {
  Duration position=const Duration(seconds:24);
  @override
  Future<void> init()async{}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options)async=>1;
  @override
  Stream<VideoEvent> videoEventsFor(int playerId)=>Stream.value(VideoEvent(eventType:VideoEventType.initialized,
    duration:const Duration(minutes:3,seconds:42),size:const Size(1920,1080)));
  @override
  Future<void> dispose(int playerId)async{}
  @override
  Future<void> play(int playerId)async{}
  @override
  Future<void> pause(int playerId)async{}
  @override
  Future<void> setLooping(int playerId,bool looping)async{}
  @override
  Future<void> setVolume(int playerId,double volume)async{}
  @override
  Future<void> setPlaybackSpeed(int playerId,double speed)async{}
  @override
  Future<void> seekTo(int playerId,Duration value)async{position=value;}
  @override
  Future<Duration> getPosition(int playerId)async=>position;
  @override
  Future<void> setMixWithOthers(bool value)async{}
  @override
  Widget buildViewWithOptions(VideoViewOptions options)=>const DecoratedBox(
    decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,
      colors:[Color(0xFF573924),Color(0xFF172E37),Color(0xFF0D161D)])),
    child:Center(child:Icon(Icons.landscape_outlined,size:96,color:Color(0xFFD0AF83))));
}
