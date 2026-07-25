// Flutter sample video editor app (trim, speed, simple effects, captions, FFmpeg export)
// Uses ffmpeg_kit_flutter_full_gpl and speech_to_text for on-device STT.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:intl/intl.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Video Editor Sample',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const EditorPage(),
    );
  }
}

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  VideoPlayerController? _controller;
  File? _videoFile;
  double _start = 0.0;
  double _end = 0.0;
  double _speed = 1.0;
  String _caption = '';
  String _effect = 'None';
  bool _exporting = false;
  String _exportLog = '';
  stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

  Future<void> _pickVideo() async {
    var status = await Permission.storage.request();
    if (!status.isGranted) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result == null) return;
    final path = result.files.single.path!;
    _videoFile = File(path);
    await _initializeController();
  }

  Future<void> _initializeController() async {
    if (_videoFile == null) return;
    _controller?.dispose();
    _controller = VideoPlayerController.file(_videoFile!);
    await _controller!.initialize();
    setState(() {
      _start = 0.0;
      _end = _controller!.value.duration.inMilliseconds.toDouble() / 1000.0;
    });
    _controller!.setLooping(true);
    _controller!.play();
  }

  void _setPlaybackSpeed(double speed) {
    _speed = speed;
    _controller?.setPlaybackSpeed(speed);
    setState(() {});
  }

  String _formatDuration(double seconds) {
    final d = Duration(milliseconds: (seconds * 1000).toInt());
    final two = (int n) => n.toString().padLeft(2, '0');
    return "${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}";
  }

  Future<String> _copyFontAssetToFile() async {
    // Copy the bundled font asset to a real file path for FFmpeg drawtext to use.
    // Make sure you add a real TTF at assets/fonts/Roboto-Regular.ttf or change this path.
    final bytes = await DefaultAssetBundle.of(context).load('assets/fonts/Roboto-Regular.ttf');
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/Roboto-Regular.ttf');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    return file.path;
  }

  String _buildAtTempoFilter(double speed) {
    if (speed <= 0) return 'atempo=1.0';
    if (speed >= 0.5 && speed <= 2.0) return 'atempo=$speed';
    List<double> parts = [];
    double remaining = speed;
    while (remaining > 2.0) {
      parts.add(2.0);
      remaining /= 2.0;
    }
    while (remaining < 0.5) {
      parts.add(0.5);
      remaining /= 0.5;
    }
    parts.add(remaining);
    return parts.map((p) => 'atempo=$p').join(',');
  }

  Future<void> _export() async {
    if (_videoFile == null) return;
    setState(() {
      _exporting = true;
      _exportLog = '';
    });

    final inPath = _videoFile!.path;
    final outDir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final outPath = '${outDir.path}/edited_$timestamp.mp4';
    final fontPath = await _copyFontAssetToFile();

    // Build video filter: speed (setpts), simple visual effect(s), drawtext
    String vfParts = '';
    final parts = <String>[];

    if (_speed != 1.0) {
      parts.add('setpts=${(1.0/_speed).toString()}*PTS');
    }

    if (_effect == 'Grayscale') {
      parts.add('hue=s=0');
    } else if (_effect == 'Sepia') {
      parts.add('colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131');
    } else if (_effect == 'Blur') {
      parts.add('boxblur=10:1');
    }

    if (_caption.isNotEmpty) {
      final escaped = _caption.replaceAll("'", "\\'").replaceAll(':', '\\:');
      parts.add("drawtext=fontfile='${fontPath}':text='${escaped}':fontcolor=white:fontsize=48:box=1:boxcolor=black@0.5:boxborderw=5:x=(w-text_w)/2:y=h-(text_h*2)");
    }

    if (parts.isNotEmpty) vfParts = parts.join(',');
    final vfArg = vfParts.isNotEmpty ? ['-vf', vfParts] : <String>[];
    final atempo = _buildAtTempoFilter(_speed);

    final cmdParts = <String>[
      '-y',
      '-ss', _start.toString(),
      '-to', _end.toString(),
      '-i', inPath,
      ...vfArg,
      '-af', atempo,
      '-c:v', 'libx264',
      '-preset', 'fast',
      '-crf', '23',
      '-c:a', 'aac',
      '-b:a', '128k',
      outPath,
    ];

    final cmd = cmdParts.map((p) => p.contains(' ') ? '"$p"' : p).join(' ');
    debugPrint('Running ffmpeg: $cmd');

    await FFmpegKit.executeAsync(cmd, (session) async {
      final returnCode = await session.getReturnCode();
      final output = await session.getAllLogsAsString();
      setState(() {
        _exporting = false;
        _exportLog = output ?? '';
      });
      if (ReturnCode.isSuccess(returnCode)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export complete: $outPath')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export failed (see log)')));
      }
    }, (log) {
      setState(() {
        _exportLog += log.getMessage() + '\n';
      });
    }, (statistics) {
      // optional
    });
  }

  Future<void> _startListening() async {
    bool available = await _speech.initialize();
    if (!available) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Speech recognition not available')));
      return;
    }
    setState(() => _isListening = true);
    _speech.listen(onResult: (result) {
      setState(() {
        _caption = result.recognizedWords;
      });
    });
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = _controller?.value.duration ?? Duration.zero;
    final currentPos = _controller?.value.position ?? Duration.zero;

    return Scaffold(
      appBar: AppBar(title: const Text('Flutter Video Editor Sample')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            if (_controller == null)
              ElevatedButton.icon(
                icon: const Icon(Icons.video_library),
                label: const Text('Pick Video'),
                onPressed: _pickVideo,
              )
            else
              AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: Stack(
                  children: [
                    VideoPlayer(_controller!),
                    if (_caption.isNotEmpty)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 30,
                        child: Container(
                          alignment: Alignment.center,
                          color: Colors.black38,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Text(
                            _caption,
                            style: const TextStyle(color: Colors.white, fontSize: 20),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            if (_controller != null) ...[
              Text('Trim: ${_formatDuration(_start)} — ${_formatDuration(_end)}'),
              RangeSlider(
                min: 0,
                max: duration.inMilliseconds.toDouble() / 1000.0,
                values: RangeValues(_start, _end),
                onChanged: (r) {
                  setState(() {
                    _start = r.start;
                    _end = r.end;
                    _controller!.seekTo(Duration(milliseconds: (_start * 1000).toInt()));
                  });
                },
              ),
              Row(
                children: [
                  const Text('Speed'),
                  Expanded(
                    child: Slider(
                      value: _speed,
                      min: 0.25,
                      max: 3.0,
                      divisions: 11,
                      label: '${_speed.toStringAsFixed(2)}x',
                      onChanged: (v) {
                        setState(() => _speed = v);
                        _setPlaybackSpeed(v);
                      },
                    ),
                  ),
                  Text('${_speed.toStringAsFixed(2)}x'),
                ],
              ),
              Row(
                children: [
                  const Text('Effect:'),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _effect,
                    items: const ['None', 'Grayscale', 'Sepia', 'Blur']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _effect = v ?? 'None';
                      });
                    },
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(_controller!.value.isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: () {
                      if (_controller!.value.isPlaying) {
                        _controller!.pause();
                      } else {
                        _controller!.play();
                      }
                      setState(() {});
                    },
                  ),
                ],
              ),
              TextField(
                decoration: const InputDecoration(labelText: 'Caption text (burn-in during export)'),
                controller: TextEditingController(text: _caption),
                onChanged: (v) => _caption = v,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton.icon(
                    icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                    label: Text(_isListening ? 'Listening...' : 'Generate Caption (STT)'),
                    onPressed: () {
                      if (_isListening) {
                        _stopListening();
                      } else {
                        _startListening();
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Export'),
                    onPressed: _exporting ? null : _export,
                  ),
                ],
              ),
              if (_exporting) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    _exportLog,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
