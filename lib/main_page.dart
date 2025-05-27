import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ride/live_detect_page.dart';
import 'package:ride/setup_page.dart';
import 'package:ride/yolo_model.dart';

class MainPage extends StatelessWidget {
  final YoloModel model;
  const MainPage({super.key, required this.model});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color.fromARGB(255, 52, 128, 215)),
        useMaterial3: true,
      ),
      home: MyMainPage(model: model),
    );
  }
}

class MyMainPage extends StatelessWidget {
  final YoloModel model;
  const MyMainPage({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    // 強制橫向 (LandscapeLeft = 逆時鐘 90 度)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
    ]);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('主畫面'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
                onPressed: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => SetUpPage(model: model)));
                },
                child: const Text('校正距離')),
            ElevatedButton(
                onPressed: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => LiveDetectPage(model: model)));
                },
                child: const Text('實時檢測')),
          ],
        ),
      ),
    );
  }
}
