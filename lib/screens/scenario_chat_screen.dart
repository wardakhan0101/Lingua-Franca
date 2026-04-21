import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:deepgram_speech_to_text/deepgram_speech_to_text.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/scenario.dart';
import '../services/ollama_api_service.dart';
import '../services/fluency_api_service.dart';
import '../services/grammar_api_service.dart';
import '../services/tts_api_service.dart';
import '../services/my_audio_source.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'unified_report_screen.dart';
import '../services/gamification_service.dart';

class ScenarioChatScreen extends StatefulWidget {
  final Scenario scenario;

  const ScenarioChatScreen({super.key, required this.scenario});

  @override
  State<ScenarioChatScreen> createState() => _ScenarioChatScreenState();
}

class _ScenarioChatScreenState extends State<ScenarioChatScreen>
    with TickerProviderStateMixin {
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _isFinished = false;
  bool _showTextInput = false; // Toggles the slide-in text field
  final FocusNode _textFocusNode = FocusNode();

  final Color primaryPurple = const Color(0xFF8A48F0);
  final Color primaryPurpleDeep = const Color(0xFF6332D1);
  final Color secondaryPurple = const Color(0xFFD9BFFF);
  final Color softBackground = const Color(0xFFF7F7FA);
  final Color textDark = const Color(0xFF101828);
  final Color textGrey = const Color(0xFF667085);

  // User avatar data (base64 photo stored in Firestore under users/{uid}).
  Uint8List? _userAvatarBytes;
  String? _userPhotoUrl;

  // STT variables
  final AudioRecorder _recorder = AudioRecorder();
  late Deepgram _deepgram;
  DeepgramLiveListener? _liveListener;
  StreamSubscription? _deepgramSubscription;
  bool _isListening = false;
  String _fullTranscript = '';
  String _currentSegment = '';

  // TTS variables
  final AudioPlayer _audioPlayer = AudioPlayer();
  String _selectedAccent = 'american';
  bool _isTtsPlaying = false; // True while AI audio is playing — blocks mic to prevent audio session conflict

  // Background Analysis Variables
  IOSink? _audioFileSink;
  StreamSubscription<List<int>>? _audioStreamSubscription;
  StreamController<List<int>>? _audioController; // Promoted to class field to prevent leaks
  String? _currentTurnAudioPath;
  final List<Map<String, dynamic>> _turnFluencyResults = [];
  final List<Future<void>> _activeFluencyTasks = []; // Track pending background tasks
  final List<String> _userTranscripts = [];
  final GamificationService _gamificationService = GamificationService();
  DateTime? _startTime;

  // Freestyle mode: soft turn limit so the AI wraps up naturally on long chats.
  int _userTurnCount = 0;
  bool _softEndNudgeSent = false;
  static const int _freestyleSoftEndAfter = 16;

  // Amplitude tracking for mic visualization — updated from record's onAmplitudeChanged.
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  double _currentAmplitude = 0.0;

  // Animation controllers. Breathing ring always runs (cheap); ripple only when TTS plays.
  late final AnimationController _micPulseController;
  late final AnimationController _ttsRippleController;

  // Track which message timestamps have already animated in, so ListView recycling
  // doesn't re-trigger the entrance animation mid-scroll.
  final Set<int> _animatedBubbleKeys = {};

  @override
  void initState() {
    super.initState();

    _micPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _ttsRippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    // Initialize system context
    _messages.add({
      "role": "system",
      "content": widget.scenario.systemPrompt,
      "isVisible": false,
    });

    // Add initial greeting from AI
    _messages.add({
      "role": "assistant",
      "content": widget.scenario.initialGreeting,
      "isVisible": true,
      "timestamp": DateTime.now(),
    });

    final sttKey = dotenv.env['STT'] ?? '';
    _deepgram = Deepgram(sttKey);

    _loadUserAvatar();

    _initAudioSession().then((_) async {
      // Pre-warm the Grammar API Cloud Run instance in the background.
      GrammarApiService.analyzeText('warmup').catchError((_) {});

      _startTime = DateTime.now(); // Start tracking session duration

      // BUGFIX: On Android, the audio hardware needs extra time to settle after
      // session configuration on first launch (Flutter startup is very heavy).
      // `addPostFrameCallback` is not sufficient because the first frame fires
      // during peak CPU load (skipping 100+ frames). A fixed delay guarantees
      // the audio subsystem is ready before we attempt playback.
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) {
        _playAiResponse(widget.scenario.initialGreeting);
      }
    });
  }

  Future<void> _loadUserAvatar() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final base64Str = doc.data()?['photoBase64'] as String?;
      if (!mounted) return;
      setState(() {
        if (base64Str != null && base64Str.isNotEmpty) {
          try {
            _userAvatarBytes = base64Decode(base64Str);
          } catch (_) {
            _userAvatarBytes = null;
          }
        }
        _userPhotoUrl = user.photoURL;
      });
    } catch (e) {
      debugPrint('Error loading user avatar: $e');
    }
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth |
          AVAudioSessionCategoryOptions.defaultToSpeaker |
          AVAudioSessionCategoryOptions.mixWithOthers,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      avAudioSessionRouteSharingPolicy:
          AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
      androidWillPauseWhenDucked: true,
    ));
  }

  // Strip hard fillers (um/uh/er/ah/hmm/mhmm and common variants) from the
  // grammar-bound transcript copy. Keeps "yeah/well/so/like/you know" since
  // those are legitimate words grammar engines can judge in context.
  static final RegExp _hardFillerPattern = RegExp(
    r'\b(u+h+m*|u+m+|e+r+|a+h+|e+h+|h+m+|m+h+m+|mm-?hmm)\b[,.\?!]?\s*',
    caseSensitive: false,
  );

  String _stripHardFillers(String text) {
    final stripped = text
        .replaceAll(_hardFillerPattern, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Normalize leading punctuation left behind (e.g., ", I went..." → "I went...")
    return stripped.replaceFirst(RegExp(r'^[,;.\s]+'), '');
  }

  void _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    if (_isListening) {
      await _stopListening();
    }

    final userMessage = text.trim();

    // Grammar API sees a filler-stripped copy; Ollama and the chat UI see the
    // original. Fluency module already catalogs fillers separately, so nothing
    // is lost from analytics by removing them here.
    final userMessageForGrammar = _stripHardFillers(userMessage);
    if (userMessageForGrammar.isNotEmpty) {
      _userTranscripts.add(userMessageForGrammar);
    }
    _userTurnCount++;

    setState(() {
      _messages.add({
        "role": "user",
        "content": userMessage,
        "isVisible": true,
        "timestamp": DateTime.now(),
      });
      _isLoading = true;
    });

    _controller.clear();
    _scrollToBottom();

    // Freestyle mode only: after ~16 user turns, drop in a hidden system nudge so the
    // AI wraps up naturally on its next 1-2 replies. The existing [END_CONVERSATION]
    // handler takes it from there. Gated by scenario id so it can't affect the
    // three scripted scenarios, whose own prompts already self-regulate length.
    if (widget.scenario.id == 'freestyle_1' &&
        _userTurnCount >= _freestyleSoftEndAfter &&
        !_softEndNudgeSent) {
      _messages.add({
        "role": "system",
        "content":
            "You've had a nice long chat. In your next 1-2 replies, warmly wrap up and end your final message with [END_CONVERSATION].",
        "isVisible": false,
      });
      _softEndNudgeSent = true;
    }

    // Prepare history for Ollama
    List<Map<String, String>> apiMessages =
        _messages.map((msg) {
          return {
            "role": msg["role"] as String,
            "content": msg["content"] as String,
          };
        }).toList();

    try {
      String response = await OllamaApiService.getResponse(apiMessages);

      bool isFinished = false;
      if (response.contains('[END_CONVERSATION]')) {
        response = response.replaceAll('[END_CONVERSATION]', '').trim();
        isFinished = true;
      }

      // Guard: user may have pressed Back while Ollama was responding
      if (!mounted) return;

      setState(() {
        if (response.isNotEmpty) {
          _messages.add({
            "role": "assistant",
            "content": response,
            "isVisible": true,
            "timestamp": DateTime.now(),
          });
          // trigger TTS playback silently
          _playAiResponse(response);
        }
        _isLoading = false;
        if (isFinished) {
          _endConversation();
        }
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add({
          "role": "system_error",
          "content": "Error: ${e.toString()}",
          "isVisible": true,
          "timestamp": DateTime.now(),
        });
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _playAiResponse(String text) async {
    if (mounted) setState(() => _isTtsPlaying = true);
    try {
      final audioBytes = await TtsApiService.synthesize(
        text: text,
        accent: _selectedAccent,
      );

      // Load bytes into just_audio player
      await _audioPlayer.setAudioSource(MyAudioSource(audioBytes));
      await _audioPlayer.play();

      // Wait for playback to actually finish before releasing the lock
      await _audioPlayer.playerStateStream.firstWhere(
        (s) => s.processingState == ProcessingState.completed || !s.playing,
      );
    } catch (e) {
      debugPrint('[TTS Error] Failed to generate/play audio: $e');
      // Don't show a snackbar for TTS failures — the conversation should still work
    } finally {
      if (mounted) setState(() => _isTtsPlaying = false);
    }
  }

  Future<bool> _checkPermission() async {
    PermissionStatus status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> _toggleRecording() async {
    if (_isListening) {
      await _stopListening();
    } else {
      // Bug fix: Block mic while AI is speaking to prevent audio session conflict
      if (_isTtsPlaying) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please wait for AI to finish speaking first.'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!await _checkPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
      }
      return;
    }

    HapticFeedback.mediumImpact();

    // The old order flipped the UI to "Listening" BEFORE the recorder was open,
    // which lost the user's first word. New order: warm up the pipeline, start
    // the mic, buffer any audio captured during the WebSocket handshake, and
    // only flip the UI once audio is actually being captured.

    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentTurnAudioPath = '${dir.path}/scenario_turn_$timestamp.wav';

      final audioFile = File(_currentTurnAudioPath!);
      if (await audioFile.exists()) {
        await audioFile.delete();
      }

      _audioFileSink = audioFile.openWrite();
      _writeWavHeader(_audioFileSink!, 0);

      // Close and replace any leftover StreamController from the previous turn.
      await _audioController?.close();
      _audioController = StreamController<List<int>>.broadcast();

      _liveListener = _deepgram.listen.liveListener(
        _audioController!.stream,
        queryParams: {
          'model': 'nova-2-general',
          'punctuate': false,
          'interim_results': true,
          'encoding': 'linear16',
          'sample_rate': 16000,
          // Tell Deepgram to transcribe fillers like "yeah", "um", "uh"
          // instead of dropping them at utterance boundaries.
          'filler_words': true,
          // Wait 300ms of silence before finalizing — prevents the model
          // from cutting off a short first word.
          'endpointing': 300,
        },
      );

      // Buffer for audio captured before the Deepgram WebSocket is ready.
      final pendingAudio = <List<int>>[];
      bool deepgramReady = false;

      // runZonedGuarded catches WebSocketChannelException from the sink side,
      // which escapes the normal onError handler because it originates from
      // writes, not the readable stream.
      runZonedGuarded(() {
        _deepgramSubscription = _liveListener!.stream.listen(
          (result) {
            final tr = result.transcript ?? '';
            debugPrint(
                '[STT] ${result.isFinal ? "FINAL" : "interim"}: "$tr"');
            if (tr.isNotEmpty) {
              if (mounted) {
                setState(() {
                  if (result.isFinal) {
                    _fullTranscript +=
                        (_fullTranscript.isEmpty ? '' : ' ') + tr;
                    _currentSegment = '';
                  } else {
                    _currentSegment = tr;
                  }
                });
              }
              _scrollToBottom();
            }
          },
          onError: (error) {
            debugPrint('Deepgram stream error: $error');
            _audioController?.close();
            _audioController = null;
            _stopListening();
          },
          cancelOnError: false,
        );

        _liveListener!.start();
      }, (error, stackTrace) {
        debugPrint('Deepgram zone error (likely WebSocket abort): $error');
        _audioController?.close();
        _audioController = null;
        if (_isListening) _stopListening();
      });

      // Start the mic BEFORE we flip the UI, so the first word is never lost.
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      _audioStreamSubscription = stream.listen((audioData) {
        // Always write to the local WAV file so fluency analysis gets the full clip.
        _audioFileSink?.add(audioData);

        // Forward to Deepgram if ready; otherwise buffer for later flush.
        if (deepgramReady &&
            _audioController != null &&
            !_audioController!.isClosed) {
          _audioController!.add(audioData);
        } else {
          pendingAudio.add(audioData);
        }
      }, onDone: () {
        _audioController?.close();
        _audioController = null;
      });

      // Drive the amplitude ring around the mic button.
      _amplitudeSubscription = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 80))
          .listen((amp) {
        if (!mounted) return;
        // amp.current is dBFS (~-60 silent, ~0 max). Normalize to 0..1 with some
        // floor so a totally quiet mic still shows gentle motion.
        final normalized = ((amp.current + 55) / 45).clamp(0.0, 1.0);
        setState(() => _currentAmplitude = normalized);
      });

      // Recorder is hot — flip UI now. Anything the user says from this moment
      // is being captured (buffered into pendingAudio until Deepgram opens).
      if (mounted) {
        setState(() {
          _isListening = true;
          _fullTranscript = '';
          _currentSegment = '';
        });
      }

      // Wait for the Deepgram WebSocket to establish, then flush buffered audio.
      await Future.delayed(const Duration(milliseconds: 400));
      deepgramReady = true;
      if (_audioController != null && !_audioController!.isClosed) {
        // Prime Deepgram's acoustic model with 250ms of silence BEFORE the
        // user's real audio arrives. Without this, short first words like
        // "yeah" land during the model's warmup window and get dropped.
        // PCM 16-bit @ 16kHz mono → 2 bytes/sample. 0.25s = 8000 bytes of 0.
        const int silencePadBytes = 8000;
        _audioController!.add(List<int>.filled(silencePadBytes, 0));
        debugPrint('[STT] Primed Deepgram with 250ms silence, '
            'flushing ${pendingAudio.length} buffered chunks '
            '(${pendingAudio.fold<int>(0, (s, c) => s + c.length)} bytes)');
        for (final chunk in pendingAudio) {
          _audioController!.add(chunk);
        }
      }
      pendingAudio.clear();

    } catch (e) {
      debugPrint('Error starting listener: $e');
      _stopListening();
    }
  }

  Future<void> _stopListening() async {
    if (!_isListening) return;

    HapticFeedback.lightImpact();

    if (mounted) {
      setState(() {
        _isListening = false;
        _currentAmplitude = 0.0;
      });
    }

    try {
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;
      await _recorder.stop();
      await _deepgramSubscription?.cancel();
      _deepgramSubscription = null;
      try { _liveListener?.close(); } catch (_) {} // WebSocket may already be dead
      _liveListener = null;
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      if (_audioFileSink != null) {
        await _audioFileSink!.flush();
        await _audioFileSink!.close();
        _audioFileSink = null;
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (_currentSegment.isNotEmpty) {
        _fullTranscript +=
            (_fullTranscript.isEmpty ? '' : ' ') + _currentSegment;
        _currentSegment = '';
      }

      final finalTranscript = _fullTranscript;

      if (mounted) {
        setState(() {
          // Clear it out for the next recording
          _fullTranscript = '';
        });

        // Auto-send the transcribed text if it's not empty
        if (finalTranscript.trim().isNotEmpty) {
          _sendMessage(finalTranscript);
        }
      }

      if (_currentTurnAudioPath != null && finalTranscript.trim().isNotEmpty) {
        await _finalizeWavFile(_currentTurnAudioPath!);
        // FIRE AND FORGET: Start background fluency analysis for this specific turn
        _processTurnFluency(_currentTurnAudioPath!);
      }
    } catch (e) {
      debugPrint('Error stopping listener: $e');
    }
  }

  void _processTurnFluency(String audioPath) {
    debugPrint("Queuing background fluency analysis for turn...");
    
    final futureObj = FluencyApiService.analyzeAudio(audioPath).then((result) {
      if (mounted) {
        _turnFluencyResults.add(result);
        debugPrint("Successfully captured fluency result for turn.");
      }
    }).catchError((e) {
      debugPrint("Background fluency analysis failed for turn: $e");
      if (mounted) {
        _turnFluencyResults.add({
          "fluency_issues": [],
          "detected_fillers": [],
          "stutters": [],
          "pauses": [],
          "fast_phrases": [],
        });
      }
    });

    _activeFluencyTasks.add(futureObj);
  }

  // --- Audio File Handling ---
  Future<void> _finalizeWavFile(String filePath) async {
    try {
      final audioFile = File(filePath);
      if (await audioFile.exists()) {
        final fileSize = await audioFile.length();
        if (fileSize > 44) {
          final bytes = await audioFile.readAsBytes();
          final header = _getWavHeaderBytes(fileSize - 44);
          for (int i = 0; i < 44 && i < header.length; i++) {
            bytes[i] = header[i];
          }
          await audioFile.writeAsBytes(bytes);
        }
      }
    } catch (e) {
      debugPrint('Error finalizing WAV file: $e');
    }
  }

  List<int> _getWavHeaderBytes(int dataSize) {
    return [
      0x52,
      0x49,
      0x46,
      0x46,
      ...(_int32ToBytes(dataSize + 36)),
      0x57,
      0x41,
      0x56,
      0x45,
      0x66,
      0x6D,
      0x74,
      0x20,
      0x10,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x01,
      0x00,
      0x80,
      0x3E,
      0x00,
      0x00,
      0x00,
      0x7D,
      0x00,
      0x00,
      0x02,
      0x00,
      0x10,
      0x00,
      0x64,
      0x61,
      0x74,
      0x61,
      ...(_int32ToBytes(dataSize)),
    ];
  }

  void _writeWavHeader(IOSink sink, int dataSize) {
    sink.add(_getWavHeaderBytes(dataSize));
  }

  List<int> _int32ToBytes(int value) {
    return [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];
  }

  void _scrollToBottom() {
    // Add a small delay to allow the ListView to build before scrolling
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _endConversation() async {
    if (_isFinished) return;

    setState(() {
      _isFinished = true;
      _isLoading = true; // Show a spinner while we compile the report
    });
    FocusScope.of(context).unfocus();
    _scrollToBottom();

    if (_userTranscripts.isEmpty) {
      setState(() => _isLoading = false);
      return; // Nothing to analyze
    }

    try {
      // 1. GRAMMAR: Batch the entire conversation transcript
      // Join with a period and space so LanguageTool can correctly identify sentence boundaries
      final fullTextToAnalyze = _userTranscripts.join(". ");
      final grammarFuture = GrammarApiService.analyzeText(
        fullTextToAnalyze,
      ).catchError((e) {
        debugPrint("Grammar API Error gracefully caught: $e");
        return GrammarAnalysisResult(
          originalText: fullTextToAnalyze,
          correctedText:
              "Grammar API is currently offline. Please try again later.",
          mistakes: [],
          summary: GrammarSummary(
            totalMistakes: 0,
            wordCount: 0,
            sentenceCount: 0,
            grammarScore: 0,
          ),
          mistakeCategories: {},
          message: e.toString(),
        );
      });

      // 2. FLUENCY: Aggregate the background queue results
      // Await all pending fluency API requests so we don't drop the latest audio turn!
      if (_activeFluencyTasks.isNotEmpty) {
        await Future.wait(_activeFluencyTasks);
      }

      List<dynamic> combinedFluencyIssues = [];
      List<dynamic> combinedFillers = [];
      List<dynamic> combinedStutters = [];
      List<dynamic> combinedPauses = [];
      List<dynamic> combinedFastPhrases = [];
      double totalSpeechRate = 0;
      int turnsWithSpeechRate = 0;
      List<String> combinedAnnotatedTranscripts = [];

      for (var result in _turnFluencyResults) {
        if (result.containsKey('fluency_issues'))
          combinedFluencyIssues.addAll(result['fluency_issues']);
        if (result.containsKey('detected_fillers'))
          combinedFillers.addAll(result['detected_fillers']);
        if (result.containsKey('stutters'))
          combinedStutters.addAll(result['stutters']);
        if (result.containsKey('pauses'))
          combinedPauses.addAll(result['pauses']);
        if (result.containsKey('fast_phrases'))
          combinedFastPhrases.addAll(result['fast_phrases']);

        if (result.containsKey('annotated_transcript')) {
          combinedAnnotatedTranscripts.add(result['annotated_transcript']);
        }

        // The unified report expects a metrics object to calculate the final score
        if (result.containsKey('metrics') &&
            result['metrics'].containsKey('avg_speech_rate')) {
          totalSpeechRate +=
              (result['metrics']['avg_speech_rate'] as num).toDouble();
          turnsWithSpeechRate++;
        }
      }

      double avgSpeechRate =
          turnsWithSpeechRate > 0
              ? (totalSpeechRate / turnsWithSpeechRate)
              : 130.0;

      final combinedFluencyResult = {
        "transcript": fullTextToAnalyze,
        "annotated_transcript": combinedAnnotatedTranscripts.join(" "),
        "fluency_issues": combinedFluencyIssues,
        "detected_fillers": combinedFillers,
        "stutters": combinedStutters,
        "pauses": combinedPauses,
        "fast_phrases": combinedFastPhrases,
        "metrics": {
          "avg_speech_rate": avgSpeechRate,
          // You might need to mock or average other metrics like grammar_errors depending on your UI
        },
      };
      final grammarResult = await grammarFuture;

      // 3. GAMIFICATION: Calculate and Save XP
      int calculatedXp = 0;
      final durationSeconds = _startTime != null 
          ? DateTime.now().difference(_startTime!).inSeconds 
          : 0;

      try {
        final xpResults = await _gamificationService.updateSessionXp(
          grammarResult: grammarResult,
          fluencyData: combinedFluencyResult,
          durationSeconds: durationSeconds,
        );
        calculatedXp = xpResults['earnedXp'] ?? 0;
      } catch (e) {
        debugPrint("Gamification Error in scenario chat: $e");
      }

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => UnifiedReportScreen(
              grammarResult: grammarResult,
              fluencyResult: combinedFluencyResult,
              audioPath: _currentTurnAudioPath, // Pass the last known clip
              earnedXp: calculatedXp,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error generating unified report: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate report: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _amplitudeSubscription?.cancel();
    _micPulseController.dispose();
    _ttsRippleController.dispose();
    _recorder.dispose();
    _deepgramSubscription?.cancel();
    _liveListener?.close();
    _audioStreamSubscription?.cancel();
    _audioController?.close(); // Cleanup the class-level StreamController
    _audioFileSink?.close();
    _controller.dispose();
    _scrollController.dispose();
    _textFocusNode.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleMessages =
        _messages.where((m) => m["isVisible"] == true).toList();

    return Scaffold(
      backgroundColor: softBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(
              widget.scenario.title,
              style: TextStyle(
                color: textDark,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              "AI Assistant",
              style: TextStyle(color: textGrey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          // ACCENT SELECTION DROPDOWN (Improved UI)
          Padding(
            padding: const EdgeInsets.only(right: 8.0, top: 8.0, bottom: 8.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: secondaryPurple.withOpacity(0.3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: primaryPurple.withOpacity(0.5)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedAccent,
                  icon: Icon(Icons.arrow_drop_down, color: primaryPurple, size: 20),
                  dropdownColor: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  alignment: Alignment.center,
                  style: TextStyle(
                    color: primaryPurple, 
                    fontWeight: FontWeight.w600, 
                    fontSize: 13
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'american', 
                      child: Row(
                        children: const [
                          Text("🇺🇸", style: TextStyle(fontSize: 16)),
                          SizedBox(width: 6),
                          Text("US"),
                        ],
                      )
                    ),
                    DropdownMenuItem(
                      value: 'british', 
                      child: Row(
                        children: const [
                          Text("🇬🇧", style: TextStyle(fontSize: 16)),
                          SizedBox(width: 6),
                          Text("UK"),
                        ],
                      )
                    ),
                    DropdownMenuItem(
                      value: 'pakistani', 
                      child: Row(
                        children: const [
                          Text("🇵🇰", style: TextStyle(fontSize: 16)),
                          SizedBox(width: 6),
                          Text("PK"),
                        ],
                      )
                    ),
                  ],
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedAccent = newValue;
                      });
                    }
                  },
                ),
              ),
            ),
          ),
          if (!_isFinished)
            Padding(
              padding: const EdgeInsets.only(right: 8.0, top: 10.0, bottom: 10.0),
              child: OutlinedButton(
                onPressed: _endConversation,
                style: OutlinedButton.styleFrom(
                  foregroundColor: textGrey,
                  side: BorderSide(color: Colors.grey.shade300, width: 1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  "End",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // Full-bleed message list. Bottom padding clears the floating mic
            // (mic column ≈ 180px tall) so the latest bubble never hides behind it.
            ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 20,
                bottom: _showTextInput ? 260 : 200,
              ),
              itemCount: visibleMessages.length +
                  (_isListening &&
                          (_fullTranscript.isNotEmpty ||
                              _currentSegment.isNotEmpty)
                      ? 1
                      : 0),
              itemBuilder: (context, index) {
                if (index < visibleMessages.length) {
                  final msg = visibleMessages[index];
                  final isUser = msg["role"] == "user";
                  final isError = msg["role"] == "system_error";

                  return _buildMessageBubble(
                    text: msg["content"],
                    isUser: isUser,
                    timestamp: msg["timestamp"] as DateTime,
                    isError: isError,
                  );
                } else {
                  // Build the live transcript bubble
                  final combinedTranscript = _fullTranscript +
                      (_currentSegment.isEmpty
                          ? ''
                          : (_fullTranscript.isEmpty ? '' : ' ') +
                              _currentSegment);
                  return _buildMessageBubble(
                    text: combinedTranscript,
                    isUser: true,
                    timestamp: DateTime.now(),
                    isError: false,
                    isLive: true,
                  );
                }
              },
            ),
            // Floating bottom input area (mic + keyboard pill, no opaque card).
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildInputArea(),
            ),
          ],
        ),
      ),
    );
  }

  // Small pill shown above the mic when the AI is typing or the report is
  // being generated. Floats over the chat background instead of sitting in a
  // solid input card.
  Widget _buildTypingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isFinished) ...[
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(primaryPurple),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Generating report...',
              style: TextStyle(
                color: primaryPurple,
                fontSize: 12,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else ...[
            _TypingDots(color: primaryPurple),
            const SizedBox(width: 10),
            Text(
              'AI Assistant is typing',
              style: TextStyle(
                color: primaryPurple,
                fontSize: 12,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageBubble({
    required String text,
    required bool isUser,
    required DateTime timestamp,
    bool isError = false,
    bool isLive = false,
  }) {
    final bubble = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      // Extra 3px at the bottom so the timestamp doesn't feel pinched against
      // the bubble's bottom corners.
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 15),
      decoration: BoxDecoration(
        color: isError
            ? Colors.red.shade100
            : (isUser ? null : Colors.white),
        gradient: (isUser && !isError)
            ? LinearGradient(
                colors: [primaryPurple, primaryPurpleDeep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isUser || isError ? 20 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 20),
        ),
        border: isLive
            ? Border.all(color: Colors.white.withOpacity(0.6), width: 1.2)
            : null,
        boxShadow: [
          if (isUser && !isError)
            BoxShadow(
              color: primaryPurple.withOpacity(0.22),
              blurRadius: 14,
              offset: const Offset(0, 4),
            )
          else
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              color: isError
                  ? Colors.red.shade900
                  : (isUser ? Colors.white : textDark),
              fontSize: 15,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          if (isLive)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _micPulseController,
                  builder: (_, __) {
                    final pulse = 0.5 +
                        0.5 *
                            math.sin(_micPulseController.value * 2 * math.pi);
                    return Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.5 + pulse * 0.5),
                        shape: BoxShape.circle,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 6),
                Text(
                  "Listening...",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.75),
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            )
          else
            Text(
              "${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}",
              style: TextStyle(
                color: isUser ? Colors.white.withOpacity(0.7) : Colors.grey,
                fontSize: 10,
              ),
            ),
        ],
      ),
    );

    // Avatar: sound-wave mark for the bot, profile picture for the user.
    // Errors render bare (no avatar) to stay visually neutral.
    final Widget avatar = isError
        ? const SizedBox.shrink()
        : (isUser ? _buildUserAvatar() : _buildBotAvatar());

    final row = Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          child: Opacity(
            opacity: isLive ? 0.88 : 1.0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: isUser
                  ? (isError
                      ? [Flexible(child: bubble)]
                      : [
                          Flexible(child: bubble),
                          const SizedBox(width: 8),
                          avatar,
                        ])
                  : [
                      avatar,
                      const SizedBox(width: 8),
                      Flexible(child: bubble),
                    ],
            ),
          ),
        ),
      ),
    );

    // Live bubble updates constantly; entrance animation would be distracting.
    if (isLive) return row;

    // One-shot entrance: fade + slide 10px from the sender's side. Keyed by
    // timestamp so ListView recycling doesn't re-trigger the animation.
    final key = timestamp.millisecondsSinceEpoch;
    final shouldAnimate = !_animatedBubbleKeys.contains(key);
    if (shouldAnimate) _animatedBubbleKeys.add(key);
    if (!shouldAnimate) return row;

    return TweenAnimationBuilder<double>(
      key: ValueKey(key),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (_, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset((isUser ? 12 : -12) * (1 - t), 0),
            child: child,
          ),
        );
      },
      child: row,
    );
  }

  // Bot identity mark: three purple vertical bars of varying heights inside a
  // white circular avatar. Replaces any generic bot icon with a brand-aligned
  // sound-wave glyph.
  Widget _buildBotAvatar() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: primaryPurple.withOpacity(0.25), width: 1),
        boxShadow: [
          BoxShadow(
            color: primaryPurple.withOpacity(0.10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: CustomPaint(
          size: const Size(16, 16),
          painter: _SoundWavePainter(color: primaryPurple),
        ),
      ),
    );
  }

  // User avatar: profile picture from Firestore (photoBase64) or Firebase Auth
  // photoURL, with a fallback person icon if neither is set.
  Widget _buildUserAvatar() {
    ImageProvider? img;
    if (_userAvatarBytes != null) {
      img = MemoryImage(_userAvatarBytes!);
    } else if (_userPhotoUrl != null && _userPhotoUrl!.isNotEmpty) {
      img = NetworkImage(_userPhotoUrl!);
    }
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: CircleAvatar(
        radius: 16,
        backgroundColor: primaryPurple.withOpacity(0.15),
        backgroundImage: img,
        child: img == null
            ? Icon(Icons.person, color: primaryPurple, size: 18)
            : null,
      ),
    );
  }


  Widget _buildInputArea() {
    if (_isFinished) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          border: Border(top: BorderSide(color: Colors.green.shade200)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Text(
              "Conversation Finished",
              style: TextStyle(
                color: Colors.green.shade700,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    final bool isMicBlocked = _isTtsPlaying || _isLoading;
    final bool showKeyboardPill = !isMicBlocked && !_isListening;

    // Transparent floating container — no opaque card. A soft top-edge fade
    // keeps the mic legible when a long message scrolls up behind it.
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            softBackground.withOpacity(0.0),
            softBackground.withOpacity(0.85),
            softBackground,
          ],
          stops: const [0.0, 0.35, 1.0],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Typing / report-generating pill hovers just above the mic.
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildTypingIndicator(),
            ),

          // ---- Mic row: keyboard pill | floating mic | balancing spacer ----
          // Spacers mirror the pill's footprint so the mic stays centered
          // regardless of pill visibility.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 44,
                child: showKeyboardPill
                    ? _buildKeyboardPill()
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 20),
              _buildFloatingMic(isMicBlocked),
              const SizedBox(width: 20),
              const SizedBox(width: 44),
            ],
          ),

          const SizedBox(height: 4),

          // ---- Status label ----
          Text(
            isMicBlocked
                ? (_isTtsPlaying ? 'AI is speaking...' : 'Thinking...')
                : (_isListening ? 'Tap to send' : 'Tap to speak'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isMicBlocked
                  ? Colors.grey.shade400
                  : (_isListening ? Colors.red : textGrey),
            ),
          ),

          // ---- Slide-in text input (AnimatedSize) ----
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _showTextInput
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 44,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                  color: primaryPurple.withOpacity(0.3)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: TextField(
                              controller: _controller,
                              focusNode: _textFocusNode,
                              style:
                                  TextStyle(color: textDark, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'Type your message...',
                                hintStyle: TextStyle(
                                  color: textGrey.withOpacity(0.5),
                                  fontSize: 13,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onSubmitted: (text) {
                                _sendMessage(text);
                                setState(() => _showTextInput = false);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _controller,
                          builder: (_, value, __) {
                            final hasText = value.text.trim().isNotEmpty;
                            return AnimatedOpacity(
                              duration: const Duration(milliseconds: 150),
                              opacity: hasText ? 1.0 : 0.3,
                              child: GestureDetector(
                                onTap: hasText
                                    ? () {
                                        _sendMessage(_controller.text);
                                        setState(() => _showTextInput = false);
                                      }
                                    : null,
                                child: CircleAvatar(
                                  radius: 21,
                                  backgroundColor: primaryPurple,
                                  child: const Icon(
                                    Icons.arrow_upward_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // Floating circular mic. Visible layout is the 80px inner puck; the outer
  // 140px SizedBox exists only to give the ripple/amplitude rings room to
  // breathe without clipping.
  Widget _buildFloatingMic(bool isMicBlocked) {
    return Tooltip(
      message: isMicBlocked
          ? (_isTtsPlaying
              ? 'Wait for AI to finish speaking'
              : 'Generating response...')
          : (_isListening ? 'Tap to send' : 'Tap to speak'),
      child: GestureDetector(
        onTap: isMicBlocked ? null : _toggleRecording,
        child: SizedBox(
          width: 140,
          height: 140,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Amplitude-reactive ring — pulses outward with the user's voice
              // while listening. RepaintBoundary keeps the amplitude tick from
              // repainting the rest of the tree.
              if (_isListening)
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _micPulseController,
                    builder: (_, __) {
                      return CustomPaint(
                        size: const Size(140, 140),
                        painter: _MicAmplitudePainter(
                          amplitude: _currentAmplitude,
                          pulse: _micPulseController.value,
                          color: Colors.red,
                        ),
                      );
                    },
                  ),
                ),
              // TTS ripple — expanding concentric rings while the AI speaks.
              if (_isTtsPlaying)
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _ttsRippleController,
                    builder: (_, __) {
                      return CustomPaint(
                        size: const Size(140, 140),
                        painter: _TtsRipplePainter(
                          progress: _ttsRippleController.value,
                          color: primaryPurple,
                        ),
                      );
                    },
                  ),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isMicBlocked
                      ? Colors.grey.shade200
                      : (_isListening
                          ? Colors.red.withOpacity(0.15)
                          : primaryPurple.withOpacity(0.10)),
                ),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isMicBlocked
                          ? Colors.grey.shade300
                          : (_isListening ? Colors.red : primaryPurple),
                      boxShadow: isMicBlocked
                          ? []
                          : [
                              BoxShadow(
                                color: (_isListening
                                        ? Colors.red
                                        : primaryPurple)
                                    .withOpacity(0.35),
                                blurRadius: 18,
                                spreadRadius: 2,
                              ),
                            ],
                    ),
                    child: Icon(
                      isMicBlocked
                          ? (_isTtsPlaying
                              ? Icons.volume_up_rounded
                              : Icons.hourglass_top_rounded)
                          : (_isListening
                              ? Icons.stop_rounded
                              : Icons.mic_rounded),
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Small secondary pill that opens the text input. Lives beside the mic so
  // learners can swap modes without hunting around.
  Widget _buildKeyboardPill() {
    return GestureDetector(
      onTap: () {
        setState(() => _showTextInput = !_showTextInput);
        if (_showTextInput) {
          Future.delayed(const Duration(milliseconds: 150), () {
            _textFocusNode.requestFocus();
          });
        } else {
          _textFocusNode.unfocus();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _showTextInput
              ? primaryPurple.withOpacity(0.15)
              : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: _showTextInput
                ? primaryPurple.withOpacity(0.5)
                : Colors.grey.shade300,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          _showTextInput
              ? Icons.close_rounded
              : Icons.keyboard_alt_outlined,
          size: 20,
          color: _showTextInput ? primaryPurple : Colors.grey.shade600,
        ),
      ),
    );
  }
}

// Three fading dots for the "AI is typing" indicator — more expressive than a
// spinner, matches the chat-app idiom learners already recognize.
class _TypingDots extends StatefulWidget {
  final Color color;
  const _TypingDots({required this.color});

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Stagger the three dots across the cycle.
            final phase = (_c.value + i * 0.18) % 1.0;
            // Tent function peaking at phase=0.5.
            final t = 1.0 - ((phase - 0.5).abs() * 2).clamp(0.0, 1.0);
            final opacity = 0.3 + 0.7 * t;
            final scale = 0.75 + 0.25 * t;
            return Padding(
              padding: EdgeInsets.only(right: i < 2 ? 4 : 0),
              child: Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// Breathing ring + amplitude-reactive ring around the mic button while
// listening. The breathing ring signals "mic is active"; the amplitude ring
// signals "mic is hearing you."
class _MicAmplitudePainter extends CustomPainter {
  final double amplitude; // 0..1 normalized audio level
  final double pulse; // 0..1 breathing cycle
  final Color color;

  _MicAmplitudePainter({
    required this.amplitude,
    required this.pulse,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const baseRadius = 40.0; // matches inner mic circle radius

    final breathing = math.sin(pulse * 2 * math.pi) * 2.5;
    final idleRadius = baseRadius + 12 + breathing;
    canvas.drawCircle(
      center,
      idleRadius,
      Paint()
        ..color = color.withOpacity(0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    if (amplitude > 0.05) {
      final ampRadius = baseRadius + 14 + amplitude * 22;
      canvas.drawCircle(
        center,
        ampRadius,
        Paint()
          ..color = color.withOpacity(0.15 + amplitude * 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 + amplitude * 3,
      );
    }
  }

  @override
  bool shouldRepaint(_MicAmplitudePainter old) =>
      old.amplitude != amplitude ||
      old.pulse != pulse ||
      old.color != color;
}

// Three concentric rings expanding outward from the mic button while TTS is
// playing — signals "AI is talking back" without needing a waveform.
class _TtsRipplePainter extends CustomPainter {
  final double progress; // 0..1 controller value
  final Color color;

  _TtsRipplePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const baseRadius = 42.0;
    const maxRadius = 66.0;

    for (int i = 0; i < 3; i++) {
      final phase = (progress + i / 3) % 1.0;
      final radius = baseRadius + phase * (maxRadius - baseRadius);
      final opacity = (1 - phase) * 0.32;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withOpacity(opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
    }
  }

  @override
  bool shouldRepaint(_TtsRipplePainter old) =>
      old.progress != progress || old.color != color;
}

// Three vertical bars of varying heights — the bot's minimalist sound-wave
// identity mark, rendered in brand purple inside the bot avatar circle.
class _SoundWavePainter extends CustomPainter {
  final Color color;

  _SoundWavePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;

    // Heights chosen so the middle bar is tallest — classic "listening" glyph.
    const heights = [0.55, 1.0, 0.7];
    const spacing = 4.5;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxBar = size.height * 0.85;

    for (int i = 0; i < 3; i++) {
      final x = cx + (i - 1) * spacing;
      final h = maxBar * heights[i];
      canvas.drawLine(
        Offset(x, cy - h / 2),
        Offset(x, cy + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SoundWavePainter old) => old.color != color;
}
