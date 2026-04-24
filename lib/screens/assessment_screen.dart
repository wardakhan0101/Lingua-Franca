import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deepgram_speech_to_text/deepgram_speech_to_text.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../models/assessment_question.dart';
import '../services/assessment_question_service.dart';
import '../services/assessment_service.dart';
import '../services/gamification_service.dart';
import 'assessment_result_screen.dart';
import 'home_screen.dart';

/// Drives the initial placement OR a level-up test. Wizard of:
/// intro → 3 grammar Qs → 3 fluency Qs → 3 pronunciation Qs → grading
/// → result screen.
enum AssessmentMode { initial, levelUp }

class AssessmentScreen extends StatefulWidget {
  const AssessmentScreen({
    super.key,
    required this.mode,
    this.targetLevel,
  }) : assert(
          mode == AssessmentMode.initial || targetLevel != null,
          'targetLevel is required for level-up mode',
        );

  final AssessmentMode mode;
  final AssessmentLevel? targetLevel;

  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

enum _Phase { loading, intro, grammar, fluency, pronunciation, grading, error }

class _AssessmentScreenState extends State<AssessmentScreen> {
  final AssessmentQuestionService _questionService = AssessmentQuestionService();
  final AssessmentService _assessmentService = AssessmentService();
  final GamificationService _gamificationService = GamificationService();
  final AudioRecorder _recorder = AudioRecorder();

  _Phase _phase = _Phase.loading;
  String _errorMessage = '';

  // Questions fetched from Firestore: 9 total — first 3 grammar, next 3 fluency, last 3 pronunciation.
  List<AssessmentQuestion> _questions = const [];
  final List<UserAnswer> _answers = [];

  // Current question within the active skill phase (0..2).
  int _indexWithinPhase = 0;

  // Recording state (shared by grammar / fluency / pronunciation phases).
  bool _isRecording = false;
  String? _currentAudioPath;
  IOSink? _audioSink;
  StreamSubscription<List<int>>? _audioSub;
  Duration _recordedDuration = Duration.zero;
  Timer? _tickTimer;
  DateTime? _recordStart;

  // Grammar phase is voice-only — Deepgram live STT instead of a TextField.
  Deepgram? _deepgram;
  DeepgramLiveListener? _liveListener;
  StreamSubscription<dynamic>? _deepgramSub;
  String _grammarTranscriptFinal = '';
  String _grammarTranscriptInterim = '';

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _audioSub?.cancel();
    _audioSink?.close();
    _deepgramSub?.cancel();
    _liveListener?.close();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    try {
      final qs = widget.mode == AssessmentMode.initial
          ? await _questionService.pickInitialQuestions()
          : await _questionService.pickLevelUpQuestions(widget.targetLevel!);
      setState(() {
        _questions = qs;
        _phase = _Phase.intro;
      });
    } catch (e) {
      setState(() {
        _phase = _Phase.error;
        _errorMessage = 'Could not load questions: $e';
      });
    }
  }

  // ---------------------------------------------------------------------
  // Phase transitions
  // ---------------------------------------------------------------------

  List<AssessmentQuestion> _questionsForSkill(AssessmentSkill skill) =>
      _questions.where((q) => q.skill == skill).toList();

  AssessmentQuestion get _currentQuestion {
    switch (_phase) {
      case _Phase.grammar:
        return _questionsForSkill(AssessmentSkill.grammar)[_indexWithinPhase];
      case _Phase.fluency:
        return _questionsForSkill(AssessmentSkill.fluency)[_indexWithinPhase];
      case _Phase.pronunciation:
        return _questionsForSkill(AssessmentSkill.pronunciation)[_indexWithinPhase];
      default:
        throw StateError('No current question in phase $_phase');
    }
  }

  void _startAssessment() {
    setState(() {
      _phase = _Phase.grammar;
      _indexWithinPhase = 0;
      _grammarTranscriptFinal = '';
      _grammarTranscriptInterim = '';
    });
  }

  void _submitGrammarAnswer() {
    final text = _grammarTranscriptFinal.trim();
    if (text.isEmpty) return;
    _answers.add(UserAnswer.grammar(_currentQuestion, text));

    final total = _questionsForSkill(AssessmentSkill.grammar).length;
    if (_indexWithinPhase + 1 < total) {
      setState(() {
        _indexWithinPhase++;
        _grammarTranscriptFinal = '';
        _grammarTranscriptInterim = '';
      });
    } else {
      setState(() {
        _phase = _Phase.fluency;
        _indexWithinPhase = 0;
        _grammarTranscriptFinal = '';
        _grammarTranscriptInterim = '';
      });
    }
  }

  void _resetGrammarTranscript() {
    setState(() {
      _grammarTranscriptFinal = '';
      _grammarTranscriptInterim = '';
    });
  }

  Future<void> _submitAudioAnswer(String audioPath) async {
    final q = _currentQuestion;
    _answers.add(
      q.skill == AssessmentSkill.fluency
          ? UserAnswer.fluency(q, audioPath)
          : UserAnswer.pronunciation(q, audioPath),
    );

    final skill = _phase == _Phase.fluency
        ? AssessmentSkill.fluency
        : AssessmentSkill.pronunciation;
    final total = _questionsForSkill(skill).length;

    if (_indexWithinPhase + 1 < total) {
      setState(() {
        _indexWithinPhase++;
        _recordedDuration = Duration.zero;
        _currentAudioPath = null;
      });
    } else if (_phase == _Phase.fluency) {
      setState(() {
        _phase = _Phase.pronunciation;
        _indexWithinPhase = 0;
        _recordedDuration = Duration.zero;
        _currentAudioPath = null;
      });
    } else {
      await _gradeAndFinish();
    }
  }

  Future<void> _gradeAndFinish() async {
    setState(() => _phase = _Phase.grading);
    try {
      final result = widget.mode == AssessmentMode.initial
          ? await _assessmentService.gradeInitial(_answers)
          : await _assessmentService.gradeLevelUp(_answers, widget.targetLevel!);

      // Persist the outcome to the user doc.
      if (widget.mode == AssessmentMode.initial) {
        final placement = result.outcome as PlacementOutcome;
        await _gamificationService.applyInitialPlacement(
          placedLevel: placement.placedLevel,
          grammarScore: result.grammarScore,
          fluencyScore: result.fluencyScore,
          pronunciationScore: result.pronunciationScore,
          composite: result.composite,
        );
      } else {
        final lu = result.outcome as LevelUpOutcome;
        await _gamificationService.handleAssessmentResult(lu.passed);
      }

      if (!mounted) return;
      // Replace the assessment screen with the result — can't go back to it.
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AssessmentResultScreen(
            mode: widget.mode,
            result: result,
            onContinue: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
              );
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = 'Grading failed: $e';
      });
    }
  }

  // ---------------------------------------------------------------------
  // Grammar phase recording — PCM stream → Deepgram live STT. No WAV file
  // saved; we only need the transcript for the grammar API call.
  // ---------------------------------------------------------------------

  Future<void> _startGrammarRecording() async {
    if (_isRecording) return;

    final micOk = await Permission.microphone.request();
    if (!micOk.isGranted) {
      _showSnack('Microphone permission required.');
      return;
    }

    final sttKey = dotenv.env['STT'];
    if (sttKey == null || sttKey.isEmpty) {
      _showSnack('Deepgram key missing — check .env (STT=...).');
      return;
    }
    _deepgram ??= Deepgram(sttKey);

    try {
      // Reset transcript state for a fresh recording.
      _grammarTranscriptFinal = '';
      _grammarTranscriptInterim = '';

      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      final broadcast = stream.asBroadcastStream();

      // Keep a subscription alive so the source stream is actively drained.
      _audioSub = broadcast.listen((_) {});

      _liveListener = _deepgram!.listen.liveListener(
        broadcast,
        queryParams: const {
          'model': 'nova-2-general',
          'punctuate': true,
          'interim_results': true,
          'encoding': 'linear16',
          'sample_rate': 16000,
        },
      );

      _deepgramSub = _liveListener!.stream.listen(
        (result) {
          final transcript = result.transcript;
          if (transcript == null || transcript.isEmpty) return;
          setState(() {
            if (result.isFinal) {
              _grammarTranscriptFinal =
                  (_grammarTranscriptFinal.isEmpty
                          ? ''
                          : '$_grammarTranscriptFinal ') +
                      transcript;
              _grammarTranscriptInterim = '';
            } else {
              _grammarTranscriptInterim = transcript;
            }
          });
        },
        onError: (e) => _showSnack('STT error: $e'),
      );
      _liveListener!.start();

      setState(() {
        _isRecording = true;
        _recordedDuration = Duration.zero;
        _recordStart = DateTime.now();
      });
      _tickTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted || _recordStart == null) return;
        setState(() {
          _recordedDuration = DateTime.now().difference(_recordStart!);
        });
      });
    } catch (e) {
      _showSnack('Could not start grammar recording: $e');
      await _stopGrammarRecording();
    }
  }

  Future<void> _stopGrammarRecording() async {
    if (!_isRecording) return;
    try {
      _tickTimer?.cancel();
      await _recorder.stop();
      await _deepgramSub?.cancel();
      _deepgramSub = null;
      _liveListener?.close();
      _liveListener = null;
      await _audioSub?.cancel();
      _audioSub = null;

      setState(() {
        _isRecording = false;
        // Any hanging interim text becomes part of the final answer.
        if (_grammarTranscriptInterim.isNotEmpty) {
          _grammarTranscriptFinal =
              (_grammarTranscriptFinal.isEmpty
                      ? ''
                      : '$_grammarTranscriptFinal ') +
                  _grammarTranscriptInterim;
          _grammarTranscriptInterim = '';
        }
      });
    } catch (e) {
      _showSnack('Could not stop grammar recording: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Recording (PCM → WAV), borrowed from timed_presentation_screen
  // ---------------------------------------------------------------------

  Future<void> _startRecording() async {
    if (_isRecording) return;

    final micOk = await Permission.microphone.request();
    if (!micOk.isGranted) {
      _showSnack('Microphone permission required.');
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final filename =
          'assessment_${DateTime.now().millisecondsSinceEpoch}_${_currentQuestion.id}.wav';
      final path = '${dir.path}/$filename';
      final file = File(path);
      if (await file.exists()) await file.delete();

      final sink = file.openWrite();
      sink.add(_wavHeader(0));
      _audioSink = sink;
      _currentAudioPath = path;

      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      _audioSub = stream.listen((chunk) {
        _audioSink?.add(chunk);
      });

      setState(() {
        _isRecording = true;
        _recordedDuration = Duration.zero;
        _recordStart = DateTime.now();
      });

      _tickTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted || _recordStart == null) return;
        setState(() {
          _recordedDuration = DateTime.now().difference(_recordStart!);
        });
      });
    } catch (e) {
      _showSnack('Could not start recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    try {
      _tickTimer?.cancel();
      await _recorder.stop();
      await _audioSub?.cancel();
      _audioSub = null;
      await _audioSink?.flush();
      await _audioSink?.close();
      _audioSink = null;

      // Patch the WAV header with the final data size so the file is playable.
      final path = _currentAudioPath;
      if (path != null) {
        await _finalizeWavHeader(File(path));
      }

      setState(() => _isRecording = false);
    } catch (e) {
      _showSnack('Could not stop recording: $e');
    }
  }

  Future<void> _finalizeWavHeader(File file) async {
    try {
      final size = await file.length();
      if (size <= 44) return;
      final bytes = await file.readAsBytes();
      final header = _wavHeader(size - 44);
      for (int i = 0; i < 44 && i < header.length; i++) {
        bytes[i] = header[i];
      }
      await file.writeAsBytes(bytes);
    } catch (_) {
      // Non-fatal — fluency engine tolerates slight header quirks.
    }
  }

  List<int> _wavHeader(int dataSize) {
    // 16 kHz, mono, 16-bit PCM header — matches timed_presentation_screen.
    return [
      0x52, 0x49, 0x46, 0x46, // "RIFF"
      ..._int32le(dataSize + 36),
      0x57, 0x41, 0x56, 0x45, // "WAVE"
      0x66, 0x6D, 0x74, 0x20, // "fmt "
      0x10, 0x00, 0x00, 0x00, // subchunk1 size = 16
      0x01, 0x00, // PCM
      0x01, 0x00, // 1 channel
      0x80, 0x3E, 0x00, 0x00, // sample rate = 16000
      0x00, 0x7D, 0x00, 0x00, // byte rate = 32000
      0x02, 0x00, // block align
      0x10, 0x00, // bits per sample
      0x64, 0x61, 0x74, 0x61, // "data"
      ..._int32le(dataSize),
    ];
  }

  List<int> _int32le(int v) => [
        v & 0xFF,
        (v >> 8) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 24) & 0xFF,
      ];

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mode == AssessmentMode.initial
            ? 'Placement Assessment'
            : 'Level Up: ${_capitalize(widget.targetLevel!.wire)}'),
        automaticallyImplyLeading: false,
        actions: widget.mode == AssessmentMode.initial
            ? [
                TextButton(
                  onPressed: _skipInitialAssessment,
                  child: const Text(
                    'Skip',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ]
            : null,
      ),
      body: SafeArea(child: _buildPhaseBody()),
    );
  }

  Future<void> _skipInitialAssessment() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(
              {'hasCompletedInitialAssessment': true},
              SetOptions(merge: true));
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _buildPhaseBody() {
    switch (_phase) {
      case _Phase.loading:
        return const Center(child: CircularProgressIndicator());
      case _Phase.error:
        return _buildErrorView();
      case _Phase.intro:
        return _buildIntroView();
      case _Phase.grammar:
        return _buildGrammarView();
      case _Phase.fluency:
      case _Phase.pronunciation:
        return _buildAudioView();
      case _Phase.grading:
        return _buildGradingView();
    }
  }

  Widget _buildErrorView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          const SizedBox(height: 16),
          Text(_errorMessage, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _phase = _Phase.loading;
                _errorMessage = '';
              });
              _loadQuestions();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildIntroView() {
    final isInitial = widget.mode == AssessmentMode.initial;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            isInitial ? 'Welcome! Let\'s place you at the right level.' : 'Ready to level up?',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Text(
            isInitial
                ? 'We\'ll give you 9 short tasks — 3 each for grammar, fluency, and pronunciation. Your composite score decides where you start.'
                : 'Pass 9 tasks at the ${_capitalize(widget.targetLevel!.wire)} level to move up. You need a composite score of ${AssessmentBands.passThresholdFor(widget.targetLevel!)}% or higher.',
          ),
          const SizedBox(height: 24),
          _bullet('Grammar — type a short answer.'),
          _bullet('Fluency — speak for the target duration.'),
          _bullet('Pronunciation — read a target sentence aloud.'),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _startAssessment,
              child: const Text('Start'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('• '),
            Expanded(child: Text(text)),
          ],
        ),
      );

  Widget _buildGrammarView() {
    final q = _currentQuestion;
    final total = _questionsForSkill(AssessmentSkill.grammar).length;
    final haveTranscript = _grammarTranscriptFinal.trim().isNotEmpty;
    final canSubmit = haveTranscript && !_isRecording;
    final displayed = _grammarTranscriptInterim.isEmpty
        ? _grammarTranscriptFinal
        : (_grammarTranscriptFinal.isEmpty
            ? _grammarTranscriptInterim
            : '$_grammarTranscriptFinal $_grammarTranscriptInterim');

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _progressHeader('Grammar', _indexWithinPhase + 1, total),
          const SizedBox(height: 16),
          Text(q.prompt, style: Theme.of(context).textTheme.titleMedium),
          if (q.instructions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(q.instructions,
                style: TextStyle(color: Colors.grey.shade700, fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 20),
          // Live transcript — populated as the user speaks. Read-only;
          // no typing anywhere in the assessment.
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SingleChildScrollView(
                child: displayed.isEmpty
                    ? Text(
                        _isRecording
                            ? 'Listening… start speaking.'
                            : 'Tap the microphone and speak your answer.',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    : RichText(
                        text: TextSpan(
                          style: const TextStyle(
                              fontSize: 16, color: Colors.black87),
                          children: [
                            TextSpan(
                              text: _grammarTranscriptFinal,
                            ),
                            if (_grammarTranscriptInterim.isNotEmpty)
                              TextSpan(
                                text: _grammarTranscriptFinal.isEmpty
                                    ? _grammarTranscriptInterim
                                    : ' $_grammarTranscriptInterim',
                                style: TextStyle(color: Colors.grey.shade500),
                              ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _isRecording
                    ? _stopGrammarRecording
                    : _startGrammarRecording,
                icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                label: Text(_isRecording
                    ? 'Stop (${_formatDuration(_recordedDuration)})'
                    : haveTranscript
                        ? 'Re-record'
                        : 'Start recording'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRecording ? Colors.redAccent : null,
                  minimumSize: const Size(200, 48),
                ),
              ),
              if (haveTranscript && !_isRecording) ...[
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _resetGrammarTranscript,
                  child: const Text('Clear'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canSubmit ? _submitGrammarAnswer : null,
              child: Text(_indexWithinPhase + 1 == total
                  ? 'Next section →'
                  : 'Next question'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioView() {
    final q = _currentQuestion;
    final isFluency = _phase == _Phase.fluency;
    final skill = isFluency ? AssessmentSkill.fluency : AssessmentSkill.pronunciation;
    final total = _questionsForSkill(skill).length;
    final minDuration = q.minDurationSeconds;
    final metMinimum = _recordedDuration.inSeconds >= minDuration;
    final haveRecording = _currentAudioPath != null && !_isRecording;
    final canSubmit = haveRecording && (isFluency ? metMinimum : true);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _progressHeader(
            isFluency ? 'Fluency' : 'Pronunciation',
            _indexWithinPhase + 1,
            total,
          ),
          const SizedBox(height: 16),
          Text(q.prompt, style: Theme.of(context).textTheme.titleMedium),
          if (q.instructions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(q.instructions,
                style: TextStyle(color: Colors.grey.shade700, fontStyle: FontStyle.italic)),
          ],
          if (!isFluency && q.targetSentence != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                q.targetSentence!,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ],
          const Spacer(),
          Center(
            child: Column(
              children: [
                Text(
                  _formatDuration(_recordedDuration),
                  style: const TextStyle(
                      fontSize: 48, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
                ),
                if (isFluency)
                  Text('Minimum: ${minDuration}s',
                      style: TextStyle(color: metMinimum ? Colors.green : Colors.grey)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _isRecording ? _stopRecording : _startRecording,
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                  label: Text(_isRecording
                      ? 'Stop'
                      : haveRecording
                          ? 'Re-record'
                          : 'Start recording'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRecording ? Colors.redAccent : null,
                    minimumSize: const Size(200, 48),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  canSubmit ? () => _submitAudioAnswer(_currentAudioPath!) : null,
              child: Text(
                _phase == _Phase.pronunciation && _indexWithinPhase + 1 == total
                    ? 'Submit assessment'
                    : _phase == _Phase.fluency && _indexWithinPhase + 1 == total
                        ? 'Next section →'
                        : 'Next question',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressHeader(String label, int current, int total) {
    final overallCurrent = _answers.length + 1;
    final overallTotal = _questions.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label ($current of $total)',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: (overallCurrent - 1) / overallTotal),
        const SizedBox(height: 4),
        Text('Question $overallCurrent of $overallTotal overall',
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _buildGradingView() {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 24),
          Text(
            'Grading your assessment...',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 8),
          Text(
            'This can take 30–60 seconds as we run grammar, fluency, and pronunciation checks.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
