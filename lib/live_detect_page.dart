import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';
import 'package:ride/yolo_model.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:image/image.dart' as img;

class LiveDetectPage extends StatefulWidget {
  final YoloModel model;
  const LiveDetectPage({super.key, required this.model});

  @override
  State<LiveDetectPage> createState() => _LiveDetectPageState();
}

class _LiveDetectPageState extends State<LiveDetectPage>
    with WidgetsBindingObserver {
  double displayWidth = 300;
  final Logger logger = Logger();
  late CameraController _controller;
  late List<CameraDescription> _cameras;
  bool _isCameraInitialized = false;
  VideoPlayerController? _videoController;
  bool _isLoading = false;
  bool _haveVideo = false;
  bool _isPlaying = false;
  final ImagePicker _imgPicker = ImagePicker();
  img.Image? tmpImage;

  var isDetecting = false;

  final soloud = SoLoud.instance;
  AudioSource? soloudAudioSource;

  @override
  void initState() {
    super.initState();
    _setUpCamera();
    _setUpSoloud();
    widget.model.clearResults();
    widget.model.predDistanceNotifier.value = 0;
    logger.i("live page init");
  }

  void _setUpCamera() async {
    try {
      _cameras = await availableCameras();
      _controller = CameraController(_cameras[0], ResolutionPreset.max);
      await _controller.initialize();
      await _controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      logger.i("camera ratio: ${_controller.value.aspectRatio}");
      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      logger.i("Error on setUpCamera : $e");
    }
  }

  void _setUpSoloud() async {
    try {
      await soloud.init();
      soloudAudioSource ??= await soloud.loadAsset("assets/notice.wav");
    } catch (e) {
      logger.i("Error on setUpSoloud : $e");
    }
  }

  @override
  void dispose() {
    if (isDetecting) _controller.stopImageStream();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Orientation orientation = MediaQuery.of(context).orientation;
    if (!_isCameraInitialized) {
      return Container();
    }
    // 直的
    else if (orientation == Orientation.portrait) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: const Text('實時監測'),
          centerTitle: true,
        ),
        body: Center(
          child: Column(
            children: [
              Stack(children: [
                SizedBox(
                  width: displayWidth * (1 / _controller.value.aspectRatio),
                  height: displayWidth,
                  child: Padding(
                    padding: const EdgeInsets.all(0.0),
                    child: CameraPreview(_controller),
                  ),
                ),
                ValueListenableBuilder<List<Widget>>(
                  valueListenable: widget.model.boxes,
                  builder: (context, boxes, child) {
                    return SizedBox(
                        width:
                            displayWidth * (1 / _controller.value.aspectRatio),
                        height: displayWidth,
                        child: Stack(children: boxes));
                  },
                ),
              ]),
              ElevatedButton(
                onPressed: () async {
                  startDetection();
                },
                child: const Text("開始實時監測"),
              ),
              ElevatedButton(
                onPressed: () async {
                  stopDetection();
                },
                child: const Text("結束實時監測"),
              ),
              Text(
                'ratio: ${widget.model.ratio.toStringAsFixed(2)}',
                textAlign: TextAlign.center,
              ),
              ElevatedButton(
                onPressed: () {
                  soloud.play3d(soloudAudioSource!, 5, 0, 0).then((handle) {
                    soloud.setVolume(handle, 5);
                  });
                },
                child: Text("soloud測試"),
              ),
              ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _controller
                          .lockCaptureOrientation(DeviceOrientation.portraitUp);
                    });
                  },
                  child: Text('校正畫面'))
            ],
          ),
        ),
      );
      // 橫的
    } else {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: const Text('實時監測'),
          centerTitle: true,
        ),
        body: Center(
          child: Row(
            children: [
              Stack(children: [
                SizedBox(
                  width: displayWidth,
                  height: displayWidth * (1 / _controller.value.aspectRatio),
                  child: CameraPreview(_controller),
                ),
                ValueListenableBuilder<List<Widget>>(
                  valueListenable: widget.model.boxes,
                  builder: (context, boxes, child) {
                    return SizedBox(
                        width: displayWidth,
                        height:
                            displayWidth * (1 / _controller.value.aspectRatio),
                        child: Stack(children: boxes));
                  },
                ),
              ]),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      startDetection();
                    },
                    child: const Text("開始實時監測"),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      stopDetection();
                    },
                    child: const Text("結束實時監測"),
                  ),
                  ElevatedButton(
                    onPressed: pickVideo,
                    child: const Text("選擇影片"),
                  ),
                  if (!_isPlaying)
                    ElevatedButton(
                      onPressed: _haveVideo
                          ? () {
                              setState(() {
                                _videoController!.play();
                                _isPlaying = true;
                              });
                            }
                          : null,
                      child: const Text("播放"),
                    )
                  else
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _videoController!.pause();
                          _isPlaying = false;
                        });
                      },
                      child: const Text("暫停"),
                    ),
                  Text(
                    'ratio: ${widget.model.ratio.toStringAsFixed(2)}',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              if (_isLoading)
                const CircularProgressIndicator()
              else if (_videoController != null &&
                  _videoController!.value.isInitialized)
                Stack(children: [
                  SizedBox(
                    width: displayWidth,
                    height: displayWidth *
                        (1 / _videoController!.value.aspectRatio),
                    child: VideoPlayer(_videoController!),
                  ),
                  ValueListenableBuilder<List<Widget>>(
                      valueListenable: widget.model.poses,
                      builder: (context, poses, child) {
                        return SizedBox(
                            width: displayWidth,
                            height: displayWidth *
                                (1 / _videoController!.value.aspectRatio),
                            child: Stack(children: poses));
                      })
                ])
              else
                ValueListenableBuilder<List<Widget>>(
                    valueListenable: widget.model.poses,
                    builder: (context, poses, child) {
                      return SizedBox(
                          width: displayWidth *
                              (1 / _controller.value.aspectRatio),
                          height: displayWidth,
                          child: Stack(children: poses));
                    })
            ],
          ),
        ),
      );
    }
  }

  Future<void> startDetection() async {
    setState(() {
      isDetecting = true;
    });
    if (_controller.value.isStreamingImages) {
      return;
    }
    await _controller.startImageStream((image) async {
      if (isDetecting && !widget.model.isBusy()) {
        widget.model.setImage = [image.width, image.height];
        widget.model.detectObjectOnFrame(
            image,
            Size(
                displayWidth,
                displayWidth *
                    (widget.model.imgHeight / widget.model.imgWidth)),
            MediaQuery.of(context).orientation,
            (_videoController != null && _videoController!.value.isInitialized)
                ? Size(displayWidth,
                    displayWidth * (1 / _videoController!.value.aspectRatio))
                : null);
      }
    });
  }

  Future<void> stopDetection() async {
    if (isDetecting) _controller.stopImageStream();
    setState(() {
      isDetecting = false;
      widget.model.clearResults();
    });
  }

  Future<void> pickVideo() async {
    final XFile? result =
        await _imgPicker.pickVideo(source: ImageSource.gallery);
    if (result == null) {
      logger.i("ERROR: Can't load video");
      return;
    }

    setState(() => _isLoading = true);

    _videoController?.dispose(); // 若之前有控制器先釋放
    _videoController = VideoPlayerController.file(File(result.path));

    await _videoController!.initialize();
    _videoController!.setLooping(true);
    setState(() {
      _isLoading = false;
      _haveVideo = true;
    });
  }
}
