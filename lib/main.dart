import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_tflite/flutter_tflite.dart';
import 'package:image/image.dart' as img;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MNIST Digit Recognizer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigoAccent),
        useMaterial3: true,
        // Set the default text theme to use a monospace font
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontFamily: 'monospace'),
          bodyMedium: TextStyle(fontFamily: 'monospace'),
          displayLarge: TextStyle(fontFamily: 'monospace'),
          displayMedium: TextStyle(fontFamily: 'monospace'),
          displaySmall: TextStyle(fontFamily: 'monospace'),
          headlineLarge: TextStyle(fontFamily: 'monospace'),
          headlineMedium: TextStyle(fontFamily: 'monospace'),
          headlineSmall: TextStyle(fontFamily: 'monospace'),
          titleLarge: TextStyle(fontFamily: 'monospace'),
          titleMedium: TextStyle(fontFamily: 'monospace'),
          titleSmall: TextStyle(fontFamily: 'monospace'),
          bodySmall: TextStyle(fontFamily: 'monospace'),
          labelLarge: TextStyle(fontFamily: 'monospace'),
          labelMedium: TextStyle(fontFamily: 'monospace'),
          labelSmall: TextStyle(fontFamily: 'monospace'),
        ),
      ),
      home: const DigitRecognizer(),
    );
  }
}

class DigitRecognizer extends StatefulWidget {
  const DigitRecognizer({super.key});

  @override
  State<DigitRecognizer> createState() => _DigitRecognizerState();
}

class _DigitRecognizerState extends State<DigitRecognizer> {
  final List<Offset?> _points = [];
  String _prediction = 'Draw a digit';
  List<double> _confidenceList = List.filled(10, 0.0);
  int? _predictedDigit;
  bool _isModelLoaded = false;
  final GlobalKey _canvasKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      String? res = await Tflite.loadModel(
        model: "assets/mnist_model.tflite",
        labels: "assets/labels.txt",
      );
      setState(() {
        _isModelLoaded = (res == "success");
      });
      debugPrint('Model loaded: $res');
    } catch (e) {
      debugPrint('Error loading model: $e');
      setState(() {
        _prediction = 'Error loading model';
      });
    }
  }

  @override
  void dispose() {
    Tflite.close();
    super.dispose();
  }

  void _clearCanvas() {
    setState(() {
      _points.clear();
      _prediction = 'Draw a digit';
      _confidenceList = List.filled(10, 0.0);
      _predictedDigit = null;
    });
  }

  Future<void> _recognizeDigit() async {
    if (!_isModelLoaded || _points.isEmpty) return;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 280, 280));
    final paint = Paint()
      ..color = Colors.white
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 20.0;

    canvas.drawRect(const Rect.fromLTWH(0, 0, 280, 280), Paint()..color = Colors.black);

    for (int i = 0; i < _points.length - 1; i++) {
      if (_points[i] != null && _points[i + 1] != null) {
        canvas.drawLine(_points[i]!, _points[i + 1]!, paint);
      }
    }

    final picture = recorder.endRecording();
    final imgUi = await picture.toImage(280, 280);
    final ByteData? byteData = await imgUi.toByteData(format: ui.ImageByteFormat.png);
    
    if (byteData == null) return;
    Uint8List pngBytes = byteData.buffer.asUint8List();

    try {
      var recognitions = await Tflite.runModelOnBinary(
        binary: pngBytesToFloat32List(pngBytes),
        numResults: 10,
        threshold: 0.0,
      );

      List<double> newScores = List.filled(10, 0.0);
      int? bestDigit;
      double maxConf = -1.0;

      if (recognitions != null) {
        for (var res in recognitions) {
          int label = int.parse(res['label']);
          double conf = res['confidence'];
          newScores[label] = conf;
          if (conf > maxConf && conf > 0.1) {
            maxConf = conf;
            bestDigit = label;
          }
        }
      }

      setState(() {
        _confidenceList = newScores;
        _predictedDigit = bestDigit;
        _prediction = bestDigit != null ? 'Prediction: $bestDigit' : 'Draw a digit';
      });
    } catch (e) {
      debugPrint('Error running model: $e');
    }
  }

  Uint8List pngBytesToFloat32List(Uint8List pngBytes) {
    img.Image? image = img.decodeImage(pngBytes);
    img.Image resized = img.copyResize(image!, width: 28, height: 28);
    
    var floatList = Float32List(28 * 28 * 1);
    
    int pixelIndex = 0;
    for (int y = 0; y < 28; y++) {
      for (int x = 0; x < 28; x++) {
        var pixel = resized.getPixel(x, y);
        int r = img.getRed(pixel);
        int g = img.getGreen(pixel);
        int b = img.getBlue(pixel);
        double luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
        floatList[pixelIndex++] = luminance;
      }
    }
    return floatList.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('✍️ Ink 2 Digit', style: TextStyle(color: Colors.white, fontFamily: 'monospace')),
        centerTitle: true,
        backgroundColor: Colors.black,
      ),
      body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_prediction, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
              const SizedBox(height: 10),
              Container(
                key: _canvasKey,
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white30, width: 3),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.black,
                ),
                child: GestureDetector(
                  onPanStart: (details) {
                    setState(() {
                      RenderBox renderBox = _canvasKey.currentContext!.findRenderObject() as RenderBox;
                      _points.add(renderBox.globalToLocal(details.globalPosition));
                    });
                  },
                  onPanUpdate: (details) {
                    setState(() {
                      RenderBox renderBox = _canvasKey.currentContext!.findRenderObject() as RenderBox;
                      Offset localPosition = renderBox.globalToLocal(details.globalPosition);
                      if (localPosition.dx >= 0 && localPosition.dx <= 280 &&
                          localPosition.dy >= 0 && localPosition.dy <= 280) {
                        _points.add(localPosition);
                      } else {
                        if (_points.isNotEmpty && _points.last != null) {
                          _points.add(null);
                        }
                      }
                    });
                  },
                  onPanEnd: (details) {
                    _points.add(null);
                    _recognizeDigit();
                  },
                  child: RepaintBoundary(
                    child: ClipRect(
                      child: CustomPaint(
                        painter: DigitPainter(points: _points),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: _clearCanvas,
                icon: const Icon(Icons.layers_clear),
                label: const Text('Clear Canvas', style: TextStyle(fontFamily: 'monospace')),
              ),
              const SizedBox(height: 10),
              _buildConfidenceBars(),
              if (!_isModelLoaded) ...[
                const SizedBox(height: 20),
                const Text('Model loading failed or still in progress...',
                  style: TextStyle(color: Colors.red, fontFamily: 'monospace')),
              ],
              const SizedBox(height: 10),
            ],
          ),
        ),
    );
  }

  Widget _buildConfidenceBars() {
    return Column(
      children: List.generate(10, (index) {
        double score = _confidenceList[index];
        bool isBest = index == _predictedDigit;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 4),
          child: Row(
            children: [
              SizedBox(width: 20, child: Text('$index', style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'))),
              const SizedBox(width: 10),
              Expanded(
                child: LinearProgressIndicator(
                  value: score,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isBest ? Colors.green : Colors.blue.withOpacity(0.5),
                  ),
                  minHeight: 12,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 55, // Increased width slightly for monospace percent
                child: Text('${(score * 100).toStringAsFixed(1)}%', style: TextStyle(
                  fontSize: 12,
                  color: isBest ? Colors.green : Colors.black54,
                  fontWeight: isBest ? FontWeight.bold : FontWeight.normal,
                  fontFamily: 'monospace',
                )),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class DigitPainter extends CustomPainter {
  final List<Offset?> points;

  DigitPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.white
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 20.0;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(DigitPainter oldDelegate) => true;
}
