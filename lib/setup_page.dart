import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gap/gap.dart';
import 'package:logger/logger.dart';
import 'yolo_model.dart';

class SetUpPage extends StatefulWidget {
  final YoloModel model;
  const SetUpPage({super.key, required this.model});
  @override
  SetupPageState createState() => SetupPageState();
}

class SetupPageState extends State<SetUpPage> {
  var logger = Logger();
  XFile? selectedImage;
  bool isImageBoxInfoGet = false;
  double displayWidth = 400;
  bool isDetectButtonEnabled = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    Orientation orientation = MediaQuery.of(context).orientation;
    if (orientation == Orientation.portrait) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: const Text('校正距離'),
          centerTitle: true,
        ),
        body: Center(
            child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            selectedImage != null
                ? Stack(children: [
                    Image.file(
                      File(selectedImage!.path), // 將 XFile 轉換為 File
                      width: displayWidth,
                      height: displayWidth *
                          (widget.model.imgHeight / widget.model.imgWidth),
                    ),
                    SizedBox(
                      width: displayWidth,
                      height: displayWidth *
                          (widget.model.imgHeight / widget.model.imgWidth),
                      child: Stack(
                        children: isImageBoxInfoGet
                            ? widget.model.renderBoxes(
                                Size(
                                    displayWidth,
                                    displayWidth *
                                        (widget.model.imgHeight /
                                            widget.model.imgWidth)),
                              )
                            : [],
                      ),
                    )
                  ])
                : Container(),
            selectedImage != null
                ? const Text(
                    '已選擇圖片',
                    textAlign: TextAlign.center,
                  )
                : const Text(
                    '按下按鈕後選擇圖片',
                    textAlign: TextAlign.center,
                  ),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  showImageSourceDialog(context);
                });
              },
              child: const Icon(Icons.image),
            ),
            if (selectedImage != null)
              OutlinedButton(
                onPressed: () {
                  showSetParamDialog(context);
                },
                child: const Text('設置參數'),
              ),
            if (selectedImage != null)
              OutlinedButton(
                onPressed: isDetectButtonEnabled
                    ? () {
                        widget.model.setDistance(Orientation.landscape);
                        setState(() {
                          isImageBoxInfoGet = true;
                        });
                      }
                    : null,
                child: const Text('偵測距離'),
              ),
            Text(
              '比例: ${widget.model.ratio.toStringAsFixed(2)}',
              textAlign: TextAlign.center,
            ),
            Text(
              '距離: ${widget.model.predDistance.toStringAsFixed(2)}',
              textAlign: TextAlign.center,
            ),
          ],
        )),
      );
    } else {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: const Text('校正距離'),
          centerTitle: true,
        ),
        body: Center(
            child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            selectedImage != null
                ? Stack(children: [
                    Image.file(
                      File(selectedImage!.path), // 將 XFile 轉換為 File
                      width: displayWidth,
                      height: displayWidth *
                          (widget.model.imgHeight / widget.model.imgWidth),
                    ),
                    SizedBox(
                      width: displayWidth,
                      height: displayWidth *
                          (widget.model.imgHeight / widget.model.imgWidth),
                      child: Stack(
                        children: isImageBoxInfoGet
                            ? widget.model.renderBoxes(
                                Size(
                                    displayWidth,
                                    displayWidth *
                                        (widget.model.imgHeight /
                                            widget.model.imgWidth)),
                              )
                            : [],
                      ),
                    )
                  ])
                : Container(),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                selectedImage != null
                    ? const Text(
                        '已選擇圖片',
                        textAlign: TextAlign.center,
                      )
                    : const Text(
                        '按下按鈕後選擇圖片',
                        textAlign: TextAlign.center,
                      ),
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      showImageSourceDialog(context);
                    });
                  },
                  child: const Icon(Icons.image),
                ),
              ],
            ),
            if (selectedImage != null)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      showSetParamDialog(context);
                    },
                    child: const Text('設置參數'),
                  ),
                  OutlinedButton(
                    onPressed: isDetectButtonEnabled
                        ? () {
                            widget.model.setDistance(Orientation.landscape);
                            setState(() {
                              isImageBoxInfoGet = true;
                            });
                          }
                        : null,
                    child: const Text('偵測距離'),
                  ),
                ],
              ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '比例: ${widget.model.ratio.toStringAsFixed(2)}',
                  textAlign: TextAlign.center,
                ),
                Text(
                  '距離: ${widget.model.predDistance.toStringAsFixed(2)}',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ],
        )),
      );
    }
  }

  void showImageSourceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('選擇一張圖片'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('從相簿中挑選'),
                onTap: () async {
                  Navigator.pop(context);
                  final ImagePicker picker = ImagePicker();
                  // 從圖庫中選擇一張圖片
                  final XFile? image =
                      await picker.pickImage(source: ImageSource.gallery);
                  if (image != null) {
                    setState(() {
                      isDetectButtonEnabled = false;
                      isImageBoxInfoGet = false;
                      selectedImage = image;
                      if (selectedImage != null) {
                        widget.model.setImgByPath = selectedImage!.path;
                      }
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('拍一張圖片'),
                onTap: () async {
                  Navigator.pop(context);
                  final ImagePicker picker = ImagePicker();
                  // 由相機拍出一張圖片
                  final XFile? image =
                      await picker.pickImage(source: ImageSource.camera);
                  if (image != null) {
                    setState(() {
                      isDetectButtonEnabled = false;
                      isImageBoxInfoGet = false;
                      selectedImage = image;
                      if (selectedImage != null) {
                        widget.model.setImgByPath = selectedImage!.path;
                      }
                    });
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void showSetParamDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('設置參數'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '已知長度',
                  hintText: '請輸入長度(cm)',
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  double? digit = double.tryParse(value);
                  widget.model.realLength = digit ?? 1;
                },
              ),
              Gap(10),
              TextField(
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '已知距離',
                  hintText: '請輸入距離(cm)',
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  double? digit = double.tryParse(value);
                  widget.model.realDistance = digit ?? 1;
                },
              ),
              ElevatedButton(
                  onPressed: () async {
                    await widget.model.detectObjectOnImage();
                    widget.model.setRatio();
                    setState(() {
                      isImageBoxInfoGet = true;
                      isDetectButtonEnabled = true;
                      Navigator.pop(context);
                    });
                  },
                  child: Text("確認")),
            ],
          ),
        );
      },
    );
  }
}
