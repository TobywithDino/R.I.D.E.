import 'package:flutter/material.dart';
import 'package:ride/main_page.dart';
import 'package:ride/yolo_model.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  YoloModel model = YoloModel();
  model.loadModel();
  runApp(MainPage(model: model));
}
