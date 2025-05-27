import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:image/image.dart' as img;

class TrackedObject {
  String id;
  List<double> box; // x1, y1, x2, y2
  String tag;
  int disappearCount = 0;

  TrackedObject({
    required this.id,
    required this.box,
    required this.tag,
  });
}

class ObjectPos {}

class YoloModel {
  late FlutterVision vision;
  Logger logger = Logger();
  File? _image;
  List<Map<String, dynamic>>? _recognitions;
  Map<String, TrackedObject> trackingObjects = {};
  int nextId = 1;
  int maxDisappearFrames = 20; // 允許最多消失 20 幀
  double iouThreshold = 0.5; // IoU 門檻
  double? _imageHeight;
  double? _imageWidth;
  bool _busy = false;

  double ratio = 0;
  double realLength = 0;
  double realDistance = 0;
  double predDistance = 0;
  ValueNotifier<double> predDistanceNotifier = ValueNotifier(0.0);
  ValueNotifier<double> predXNotifier = ValueNotifier(0.0);

  ValueNotifier<List<Widget>> boxes = ValueNotifier([]);
  ValueNotifier<List<Widget>> poses = ValueNotifier([]);
  final soloud = SoLoud.instance;
  AudioSource? soloudAudioSource;

  // 載入YOLO模型
  Future<void> loadModel() async {
    vision = FlutterVision();
    try {
      await vision.loadYoloModel(
          labels: 'assets/labels_tmp.txt',
          modelPath: 'assets/yolov8n_int8.tflite',
          modelVersion: "yolov8",
          quantization: true,
          numThreads: 2,
          useGpu: true); // TODO: 測試看看後三個參數對效能的提升
      await soloud.init();
      soloudAudioSource = await soloud.loadAsset("assets/notice.wav");
      logger.i('Model loaded!');
    } catch (e) {
      logger.i("Failed to load YOLO model: $e");
    }
  }

  // 檢測圖片中的物件，並將結果傳入_recognitions中
  Future<void> detectObjectOnImage() async {
    try {
      _busy = true;

      Uint8List byte = await _image!.readAsBytes();

      final recognitions = await vision.yoloOnImage(
          bytesList: byte,
          imageHeight: _imageHeight!.toInt(),
          imageWidth: _imageWidth!.toInt(),
          iouThreshold: 0.6,
          confThreshold: 0.4,
          classThreshold: 0.2);
      _recognitions = recognitions;
      for (var box in _recognitions!) {
        box["x"] = 0.0;
        box["distance"] = 0.0;
      }

      if (_recognitions == null) {
        logger.i(
            "detectObjectOnImage: Detection failed : _recognitions is null.");
      } else if (_recognitions!.isEmpty) {
        logger.i(
            "detectObjectOnImage: Detected nothing : _recognitions is empty.");
      } else {
        logger.i('detectObjectOnImage: detected');
      }
      _busy = false;
    } catch (e) {
      logger.i("Error on detectObjectOnImage: $e");
      _busy = false;
    }
  }

  void updateRecognitions(List<Map<String, dynamic>> newRecognitions) {
    _recognitions = List.empty(growable: true);
    Map<String, dynamic> tmp = {};
    for (var detection in newRecognitions) {
      List<double> box = detection["box"];
      String tag = detection["tag"];
      tmp = {
        "box": box,
        "tag": tag,
        "x": 0.0,
        "distance": 0.0,
      };
      _recognitions!.add(tmp);
    }
  }

  Future<void> detectObjectOnFrame(CameraImage cameraImage, Size size,
      Orientation orientation, Size? demoWindow) async {
    _busy = true;
    List<Uint8List> rotatedByteLists = rotateYUV420(cameraImage);

    try {
      final recognitions = await vision.yoloOnFrame(
          bytesList: rotatedByteLists,
          imageHeight: cameraImage.width,
          imageWidth: cameraImage.height,
          iouThreshold: 0.2,
          confThreshold: 0.1,
          classThreshold: 0.3);

      updateRecognitions(recognitions);
    } catch (e) {
      logger.i("Error on detectObjectOnFrame(yoloOnFrame): $e");
      _busy = false;
    }

    if (_recognitions == null) {
      logger
          .i("detectObjectOnFrame: Detection failed : _recognitions is null.");
    } else if (_recognitions!.isEmpty) {
      logger
          .i("detectObjectOnFrame: Detected nothing : _recognitions is empty.");
    } else {
      logger.i('detectObjectOnFrame: detected');
    }
    _busy = false;

    setDistance(orientation);
    renderBoxes(size);
    renderPoses(demoWindow ?? size);
    _warnWithSound();
  }

  Future<void> detectObjectOnFrameByImage(
      CameraImage cameraImage, Size size, Orientation orientation) async {
    try {
      _busy = true;
      Uint8List bytes = img.encodeJpg(convertYUV420ToImage(cameraImage));

      final recognitions = await vision.yoloOnImage(
          bytesList: bytes,
          imageHeight: cameraImage.height,
          imageWidth: cameraImage.width,
          iouThreshold: 0.4,
          confThreshold: 0.1,
          classThreshold: 0.5);

      updateRecognitions(recognitions);

      if (_recognitions == null) {
        logger.i(
            "detectObjectOnFrame: Detection failed : _recognitions is null.");
      } else if (_recognitions!.isEmpty) {
        logger.i(
            "detectObjectOnFrame: Detected nothing : _recognitions is empty.");
      }
      _busy = false;
    } catch (e) {
      logger.i("Error on detectObjectOnFrame: $e");
      _busy = false;
    }

    setDistance(orientation);
    renderBoxes(size);
    _warnWithSound();
  }

  img.Image convertYUV420ToImage(CameraImage cameraImage) {
    final imageWidth = cameraImage.width;
    final imageHeight = cameraImage.height;

    final yBuffer = cameraImage.planes[0].bytes;
    final uBuffer = cameraImage.planes[1].bytes;
    final vBuffer = cameraImage.planes[2].bytes;

    final int yRowStride = cameraImage.planes[0].bytesPerRow; // 1440
    final int yPixelStride = cameraImage.planes[0].bytesPerPixel!; // 1

    final int uvRowStride = cameraImage.planes[1].bytesPerRow; // 1440
    final int uvPixelStride = cameraImage.planes[1].bytesPerPixel!; // 2

    final image = img.Image(width: imageWidth, height: imageHeight);

    for (int h = 0; h < imageHeight; h++) {
      int uvh = (h / 2).floor();

      for (int w = 0; w < imageWidth; w++) {
        int uvw = (w / 2).floor();

        final yIndex = (h * yRowStride) + (w * yPixelStride);

        final int y = yBuffer[yIndex];

        final int uvIndex = (uvh * uvRowStride) + (uvw * uvPixelStride);
        final int u = uBuffer[uvIndex];
        final int v = vBuffer[uvIndex];

        List<int> rgb = yuv2rgb(y, u, v);
        image.setPixelRgb(w, h, rgb[0], rgb[1], rgb[2]);
      }
    }

    return image;
  }

  img.Image convertYUV420ByteListToImage(List<Uint8List> yuv) {
    final imageWidth = 1080;
    final imageHeight = 1440;

    final yBuffer = yuv[0]; // len = 1555200
    final uBuffer = yuv[1]; // len = 777600
    final vBuffer = yuv[2]; // len = 777600

    final int yRowStride = 1080;
    final int yPixelStride = 1;

    final int uvRowStride = 1080 ~/ 2;
    final int uvPixelStride = 1;

    final image = img.Image(width: imageWidth, height: imageHeight);

    for (int h = 0; h < imageHeight; h++) {
      int uvh = (h / 2).floor(); // 逆時鐘旋轉90度，取h應該要/2 +1
      for (int w = 0; w < imageWidth; w++) {
        int uvw = (w / 2).floor();

        final yIndex = (h * yRowStride) + (w * yPixelStride);

        final int y = yBuffer[yIndex];

        final int uvIndex =
            (uvh * 2 * uvRowStride + uvRowStride) + (uvw * uvPixelStride);

        final int v = vBuffer[uvIndex];
        final int u = uBuffer[uvIndex];

        List<int> rgb = yuv2rgb(y, u, v);
        image.setPixelRgb(w, h, rgb[0], rgb[1], rgb[2]);
      }
    }
    return image;
  }

  List<Uint8List> rotateYUV420(CameraImage image) {
    final width = image.width; // 1440
    final height = image.height; // 1080

    final yPlane = image.planes[0].bytes;

    final uPlaneOld = image.planes[1].bytes;
    final newULength = uPlaneOld.length + 1;
    final uPlane = Uint8List(newULength);
    uPlane.setRange(0, uPlaneOld.length, uPlaneOld); // 複製原資料
    uPlane[uPlane.length - 1] = 0; // 最後一個補上 0

    final vPlaneOld = image.planes[2].bytes;
    final newVLength = vPlaneOld.length + 1;
    final vPlane = Uint8List(newVLength);
    vPlane.setRange(0, vPlaneOld.length, vPlaneOld); // 複製原資料
    vPlane[vPlane.length - 1] = 0; // 最後一個補上 0

    final rotatedY = Uint8List(yPlane.length); // len = 1555200
    final rotatedU = Uint8List(uPlane.length); // len = 777600
    final rotatedV = Uint8List(vPlane.length); // len = 777600

    // Rotate Y (亮度)
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final newX = y;
        final newY = width - x - 1;
        rotatedY[newY * height + newX] = yPlane[y * width + x];
      }
    }

    final uvWidth = width;
    final uvHeight = height ~/ 2;

    // Rotate U V
    for (int y = 0; y < uvHeight; y++) {
      for (int x = 0; x < uvWidth; x++) {
        final newX = y;
        final newY = uvWidth - x - 1;
        rotatedU[newY * uvHeight + newX] = uPlane[y * uvWidth + x];
        rotatedV[newY * uvHeight + newX] = vPlane[y * uvWidth + x];
      }
    }

    return [rotatedY, rotatedU, rotatedV];
  }

  List<int> yuv2rgb(int y, int u, int v) {
    // Compute RGB values per formula above.
    int r = (y + v * 1436 / 1024 - 179).round();
    int g = (y - u * 46549 / 131072 + 44 - v * 93604 / 131072 + 91).round();
    int b = (y + u * 1814 / 1024 - 227).round();

    r = r.clamp(0, 255);
    g = g.clamp(0, 255);
    b = b.clamp(0, 255);
    return List<int>.of([r, g, b]);
  }

  // 獲得圖片的寬高資訊
  void setImageDimensions() {
    if (_image == null) {
      logger.i("Error on setImageDimensions: _image coud not be null!");
      return;
    }

    FileImage(_image!)
        .resolve(const ImageConfiguration())
        .addListener(ImageStreamListener((ImageInfo info, bool _) {
      _imageHeight = info.image.height.toDouble();
      _imageWidth = info.image.width.toDouble();
    }));
  }

  // 從選取的圖片中取得參數比例，若圖片中有多個目標(車輛)，則選擇信心度最高者
  void setRatio() async {
    if (_recognitions == null || _recognitions!.isEmpty) {
      logger.i("Error on setRatio: nothing detected. Can't set ratio");
      return;
    }
    double measuredLength = 1;
    double maxConfidence = 0;
    List<Map<String, dynamic>>? theCar;
    for (var box in _recognitions!) {
      if (box["tag"] == "car" && box["box"][4] > maxConfidence) {
        maxConfidence = box["box"][4];
        measuredLength = (box["box"][2] - box["box"][0]) / imgWidth;
        theCar = [box];
      }
    }

    ratio = (measuredLength * realDistance) / realLength;

    _recognitions = theCar; // 只渲染最有信心的車車

    if (theCar != null) {
      logger.i('confidence: ${theCar[0]["box"][4]}');
    }
  }

  // 取得預測距離
  void setDistance(Orientation orientation) {
    if (_recognitions == null) {
      logger.i("ERROR: nothing detected. Can't set distance");
      return;
    }

    bool isHorizontal = orientation == Orientation.landscape;
    double measuredLength = 1;
    double measuredX = 1;
    for (var box in _recognitions!) {
      if (box["tag"] == "car" || box["tag"] == "truck" || box["tag"] == "bus") {
        measuredLength = (box["box"][2] - box["box"][0]) /
            (isHorizontal
                ? imgWidth
                : imgHeight); // TODO:因為相機的imgWidth永遠是比較長的那邊
        measuredX =
            (((box["box"][0] + box["box"][2]) / 2) - (imgWidth / 2)) / imgWidth;
        box["distance"] = (realLength * ratio) / measuredLength;
        box["x"] = (box["distance"] / ratio) * measuredX;
      }
    }
    if (measuredLength == 1 || measuredX == 1) {
      return;
    }

    predDistance = (realLength * ratio) / measuredLength;

    predDistanceNotifier.value = predDistance;
    predXNotifier.value = (predDistance / ratio) * measuredX;
  }

  // 畫出YOLO模型偵測的圖片框框
  List<Widget> renderBoxes(Size screen) {
    if (_recognitions == null) logger.i("Detection error.......");

    if (_recognitions == null || _imageHeight == null || _imageWidth == null) {
      return [];
    }

    boxes.value = _recognitions!.map((re) {
      double ratioX = re["box"][0] / imgHeight;
      double ratioW = (re["box"][2] - re["box"][0]) / imgHeight;
      double ratioY = re["box"][1] / imgWidth;
      double ratioH = (re["box"][3] - re["box"][1]) / imgWidth;

      double x, y, w, h;
      x = ratioX * screen.height;
      y = ratioY * screen.width;
      w = ratioW * screen.height;
      h = ratioH * screen.width;
      // logger.i("$x $y $w $h");
      return Positioned(
        left: math.max(0, x),
        top: math.max(0, y),
        width: w,
        height: h,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: Color.fromRGBO(37, 213, 253, 1.0),
              width: 3.0,
            ),
          ),
          child: Text(
            "${re["tag"]}\n${(re["box"][4] * 100).toStringAsFixed(0)}%\nx:${re["x"].toStringAsFixed(1)}\ndistance:${re["distance"].toStringAsFixed(1)}",
            style: TextStyle(
              color: Color.fromRGBO(37, 213, 253, 1.0),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }).toList();

    return boxes.value;
  }

  // 畫出YOLO模型偵測的圖片框框
  List<Widget> renderPoses(Size screen) {
    if (_recognitions == null) logger.i("Detection error.......");

    if (_recognitions == null || _imageHeight == null || _imageWidth == null) {
      return [];
    }

    poses.value = _recognitions!.map((re) {
      if (re["tag"] != "truck" && re["tag"] != "car" && re["tag"] != "bus") {
        return SizedBox.shrink();
      }
      double ratioX = re["distance"] / 3200;
      double ratioY = 0.5 + re["x"] / 1800;
      logger.i("RX: $ratioX, RY: $ratioY");
      double x, y;
      x = ratioX * screen.width;
      y = ratioY * screen.height;
      return Positioned(
        left: x,
        top: y,
        width: 2,
        height: 2,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: Color.fromRGBO(37, 213, 253, 1.0),
              width: 3.0,
            ),
          ),
        ),
      );
    }).toList();

    return poses.value;
  }

  void _warnWithSound() {
    for (var box in _recognitions!) {
      if (box["tag"] != 'car' && box["tag"] != 'truck' && box["tag"] != 'bus') {
        continue;
      }
      double x = box["x"];
      double y = box["distance"];
      soloud.play3d(soloudAudioSource!, x, y, 0);
    }
  }

  // 釋放模型資源
  Future<void> dispose() async {
    await vision.closeYoloModel();
  }

  // 判斷模型是否忙碌中
  bool isBusy() => _busy;

  // 獲得當前圖片
  File? getImage() => _image;

  // 設定此類別要檢測的圖片(傳入Path)
  set setImgByPath(String path) {
    _image = File(path);
    setImageDimensions();
    logger.i("_image loaded");
  }

  // 設定此類別要檢測的圖片(傳入List)
  set setImage(List<int> image) {
    _imageWidth = image[0].toDouble();
    _imageHeight = image[1].toDouble();
  }

  void clearResults() {
    if (_recognitions == null) {
      return;
    }
    _recognitions!.clear();
    boxes.value.clear();
  }

  double get imgWidth => (_imageWidth == null ? 1 : _imageWidth!);
  double get imgHeight => (_imageHeight == null ? 1 : _imageHeight!);
}
