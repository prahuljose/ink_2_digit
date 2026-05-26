import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_tflite/flutter_tflite.dart';
import 'package:image/image.dart' as img;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ink 2 Digit',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
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
  // Each element is one complete stroke (list of points).
  final List<List<Offset>> _strokes = [];
  // Points for the stroke currently being drawn.
  final List<Offset> _currentStroke = [];

  List<double> _confidenceList = List.filled(10, 0.0);
  int? _predictedDigit;
  bool _isModelLoaded = false;
  bool _isProcessing = false;
  String? _modelError;

  final GlobalKey _canvasKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  @override
  void dispose() {
    Tflite.close();
    super.dispose();
  }

  Future<void> _loadModel() async {
    try {
      final res = await Tflite.loadModel(
        model: 'assets/mnist_model.tflite',
        labels: 'assets/labels.txt',
      );
      setState(() => _isModelLoaded = res == 'success');
    } catch (e) {
      setState(() => _modelError = 'Failed to load model');
    }
  }

  bool get _hasDrawing => _strokes.isNotEmpty || _currentStroke.isNotEmpty;

  void _clearCanvas() {
    setState(() {
      _strokes.clear();
      _currentStroke.clear();
      _confidenceList = List.filled(10, 0.0);
      _predictedDigit = null;
    });
  }

  void _undoStroke() {
    if (_strokes.isEmpty) return;
    setState(() {
      _strokes.removeLast();
      _confidenceList = List.filled(10, 0.0);
      _predictedDigit = null;
    });
    if (_strokes.isNotEmpty) _recognizeDigit();
  }

  Future<void> _recognizeDigit() async {
    if (!_isModelLoaded || _strokes.isEmpty) return;
    setState(() => _isProcessing = true);

    try {
      final recorder = ui.PictureRecorder();
      final offscreen = Canvas(recorder, const Rect.fromLTWH(0, 0, 280, 280));
      offscreen.drawRect(
        const Rect.fromLTWH(0, 0, 280, 280),
        Paint()..color = Colors.black,
      );

      final strokePaint = Paint()
        ..color = Colors.white
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 20.0
        ..style = PaintingStyle.stroke;

      for (final stroke in _strokes) {
        if (stroke.length == 1) {
          offscreen.drawCircle(stroke[0], 10, Paint()..color = Colors.white);
        } else {
          offscreen.drawPath(_buildStrokePath(stroke), strokePaint);
        }
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(280, 280);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        setState(() => _isProcessing = false);
        return;
      }

      final recognitions = await Tflite.runModelOnBinary(
        binary: _pngToFloat32(byteData.buffer.asUint8List()),
        numResults: 10,
        threshold: 0.0,
      );

      final newScores = List.filled(10, 0.0);
      int? bestDigit;
      double maxConf = -1.0;

      if (recognitions != null) {
        for (final r in recognitions) {
          final label = int.parse(r['label'] as String);
          final conf = r['confidence'] as double;
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
        _isProcessing = false;
      });
    } catch (e) {
      debugPrint('Recognition error: $e');
      setState(() => _isProcessing = false);
    }
  }

  // Smooth quadratic bezier path through a stroke's points.
  Path _buildStrokePath(List<Offset> stroke) {
    final path = Path();
    if (stroke.length < 2) return path;
    path.moveTo(stroke[0].dx, stroke[0].dy);
    for (int i = 0; i < stroke.length - 1; i++) {
      final mid = Offset(
        (stroke[i].dx + stroke[i + 1].dx) / 2,
        (stroke[i].dy + stroke[i + 1].dy) / 2,
      );
      path.quadraticBezierTo(stroke[i].dx, stroke[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(stroke.last.dx, stroke.last.dy);
    return path;
  }

  Uint8List _pngToFloat32(Uint8List pngBytes) {
    final decoded = img.decodeImage(pngBytes)!;
    final resized = img.copyResize(decoded, width: 28, height: 28);
    final floatList = Float32List(28 * 28);
    for (int y = 0; y < 28; y++) {
      for (int x = 0; x < 28; x++) {
        final pixel = resized.getPixel(x, y);
        floatList[y * 28 + x] =
            (0.299 * img.getRed(pixel) + 0.587 * img.getGreen(pixel) + 0.114 * img.getBlue(pixel)) /
                255.0;
      }
    }
    return floatList.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screenW = MediaQuery.of(context).size.width;
    final canvasSize = (screenW - 48).clamp(200.0, 300.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Ink 2 Digit',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildPredictionCard(cs),
              const SizedBox(height: 16),
              _buildCanvas(canvasSize, cs),
              const SizedBox(height: 12),
              _buildControls(),
              const SizedBox(height: 20),
              _buildConfidenceBars(cs, canvasSize),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPredictionCard(ColorScheme cs) {
    final Widget content;
    final Color cardColor;

    if (_modelError != null) {
      cardColor = cs.errorContainer;
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: cs.onErrorContainer),
          const SizedBox(width: 8),
          Text(_modelError!, style: TextStyle(color: cs.onErrorContainer)),
        ],
      );
    } else if (!_isModelLoaded) {
      cardColor = cs.surfaceContainerHighest;
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
          ),
          const SizedBox(width: 10),
          Text('Loading model...', style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      );
    } else if (_isProcessing) {
      cardColor = cs.surfaceContainerHighest;
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
          ),
          const SizedBox(width: 10),
          Text('Thinking...', style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      );
    } else if (_predictedDigit != null) {
      cardColor = cs.primaryContainer;
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$_predictedDigit',
            style: TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.bold,
              color: cs.onPrimaryContainer,
              height: 1,
            ),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Predicted', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              Text(
                '${(_confidenceList[_predictedDigit!] * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
              Text('confidence', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ],
          ),
        ],
      );
    } else {
      cardColor = cs.surfaceContainerHighest;
      content = Text(
        _hasDrawing ? "Hmm, not sure..." : "Draw a digit below",
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      height: 112,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(child: content),
    );
  }

  Widget _buildCanvas(double size, ColorScheme cs) {
    return Container(
      key: _canvasKey,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: cs.shadow,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: GestureDetector(
          onPanStart: (d) {
            final box = _canvasKey.currentContext!.findRenderObject() as RenderBox;
            setState(() {
              _currentStroke.clear();
              _currentStroke.add(box.globalToLocal(d.globalPosition));
            });
          },
          onPanUpdate: (d) {
            final box = _canvasKey.currentContext!.findRenderObject() as RenderBox;
            final pos = box.globalToLocal(d.globalPosition);
            if (pos.dx >= 0 && pos.dx <= size && pos.dy >= 0 && pos.dy <= size) {
              setState(() => _currentStroke.add(pos));
            }
          },
          onPanEnd: (_) {
            if (_currentStroke.isNotEmpty) {
              setState(() {
                _strokes.add(List.of(_currentStroke));
                _currentStroke.clear();
              });
              _recognizeDigit();
            }
          },
          child: Stack(
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  painter: DigitPainter(
                    strokes: _strokes,
                    currentStroke: _currentStroke,
                    buildPath: _buildStrokePath,
                  ),
                  size: Size(size, size),
                ),
              ),
              if (!_hasDrawing)
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.draw_outlined, color: Color(0x33FFFFFF), size: 32),
                      SizedBox(height: 8),
                      Text(
                        'Draw here',
                        style: TextStyle(color: Color(0x33FFFFFF), fontSize: 16, letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _strokes.isNotEmpty ? _undoStroke : null,
            icon: const Icon(Icons.undo, size: 18),
            label: const Text('Undo'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: _hasDrawing ? _clearCanvas : null,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Clear'),
          ),
        ),
      ],
    );
  }

  Widget _buildConfidenceBars(ColorScheme cs, double canvasSize) {
    return SizedBox(
      width: canvasSize,
      height: 110,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(10, (i) => _buildBar(i, cs)),
      ),
    );
  }

  Widget _buildBar(int digit, ColorScheme cs) {
    final isBest = digit == _predictedDigit;
    const maxH = 72.0;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: _confidenceList[digit]),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
      builder: (_, value, _) {
        final barH = (value * maxH).clamp(2.0, maxH);
        return SizedBox(
          width: 24,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                isBest ? '${(value * 100).round()}%' : '',
                style: TextStyle(
                  fontSize: 8,
                  color: cs.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 20,
                height: barH,
                decoration: BoxDecoration(
                  color: isBest ? cs.primary : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$digit',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isBest ? FontWeight.bold : FontWeight.normal,
                  color: isBest ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class DigitPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;
  final Path Function(List<Offset>) buildPath;

  const DigitPainter({
    required this.strokes,
    required this.currentStroke,
    required this.buildPath,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 20.0
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()..color = Colors.white;

    for (final stroke in strokes) {
      if (stroke.length == 1) {
        canvas.drawCircle(stroke[0], 10, dotPaint);
      } else {
        canvas.drawPath(buildPath(stroke), paint);
      }
    }

    if (currentStroke.length == 1) {
      canvas.drawCircle(currentStroke[0], 10, dotPaint);
    } else if (currentStroke.length > 1) {
      canvas.drawPath(buildPath(currentStroke), paint);
    }
  }

  @override
  bool shouldRepaint(DigitPainter old) => true;
}
