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
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_card.dart';
import '../widgets/primary_button.dart';
import 'assessment_result_screen.dart';
import 'root_scaffold.dart';

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

class _AssessmentScreenState extends State<AssessmentScreen>
    with TickerProviderStateMixin {
  final AssessmentQuestionService _questionService = AssessmentQuestionService();
  final AssessmentService _assessmentService = AssessmentService();
  final GamificationService _gamificationService = GamificationService();
  final AudioRecorder _recorder = AudioRecorder();

  // Pulsing red ring around the mic while recording. Subtle, breathes once
  // per ~1.6s — adds life without being distracting on a slow page.
  late final AnimationController _pulseController;

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
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _loadQuestions();
  }

  @override
  void dispose() {
    _pulseController.dispose();
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
      // Result screen handles "Continue to Home" with its own BuildContext;
      // a captured callback from here would point at a disposed state after
      // pushReplacement runs.
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AssessmentResultScreen(
            mode: widget.mode,
            result: result,
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

  // Maps a phase to its position in the visible 5-step progress indicator
  // (Intro → Grammar → Fluency → Pronunciation → Result).
  int get _phaseStepIndex {
    switch (_phase) {
      case _Phase.intro:
        return 0;
      case _Phase.grammar:
        return 1;
      case _Phase.fluency:
        return 2;
      case _Phase.pronunciation:
        return 3;
      case _Phase.grading:
        return 4;
      case _Phase.loading:
      case _Phase.error:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeroHeader(),
            Expanded(child: _buildPhaseBody()),
          ],
        ),
      ),
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
      MaterialPageRoute(builder: (_) => const RootScaffold()),
      (route) => false,
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _buildHeroHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl, AppSpacing.lg, AppSpacing.lg, AppSpacing.xl,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.mode == AssessmentMode.initial
                      ? 'Placement Assessment'
                      : 'Level Up: ${_capitalize(widget.targetLevel!.wire)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (widget.mode == AssessmentMode.initial)
                TextButton(
                  onPressed: _skipInitialAssessment,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.xs,
                    ),
                  ),
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildPhaseIndicator(),
        ],
      ),
    );
  }

  Widget _buildPhaseIndicator() {
    const labels = ['Intro', 'Grammar', 'Fluency', 'Pron.', 'Result'];
    final activeIdx = _phaseStepIndex;
    final children = <Widget>[];
    for (int i = 0; i < labels.length; i++) {
      final completed = i < activeIdx;
      final current = i == activeIdx;
      children.add(
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: current ? 14 : 10,
                height: current ? 14 : 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: completed || current
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.3),
                  border: current
                      ? Border.all(color: Colors.white, width: 2)
                      : null,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                labels[i],
                style: TextStyle(
                  color: completed || current
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.6),
                  fontSize: 10.5,
                  fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
      if (i < labels.length - 1) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Container(
              width: 14,
              height: 1,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        );
      }
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _buildPhaseBody() {
    switch (_phase) {
      case _Phase.loading:
        return const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        );
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
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline,
              size: 56, color: AppColors.danger),
          const SizedBox(height: AppSpacing.lg),
          Text(_errorMessage,
              textAlign: TextAlign.center, style: AppTextStyles.body),
          const SizedBox(height: AppSpacing.xxl),
          PrimaryButton(
            label: 'Retry',
            onPressed: () {
              setState(() {
                _phase = _Phase.loading;
                _errorMessage = '';
              });
              _loadQuestions();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildIntroView() {
    final isInitial = widget.mode == AssessmentMode.initial;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isInitial
                      ? "Welcome — let's find your level"
                      : 'Ready to level up?',
                  style: AppTextStyles.display,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  isInitial
                      ? '9 short tasks across grammar, fluency, and pronunciation. Your composite score decides where you start.'
                      : 'Pass 9 tasks at the ${_capitalize(widget.targetLevel!.wire)} level — composite score ${AssessmentBands.passThresholdFor(widget.targetLevel!)}% or higher.',
                  style: AppTextStyles.body,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _phaseTile(
            Icons.edit_note_rounded,
            'Grammar',
            '3 questions, voice answers',
            AppColors.primary,
          ),
          const SizedBox(height: AppSpacing.md),
          _phaseTile(
            Icons.mic_external_on_rounded,
            'Fluency',
            '3 spoken responses',
            AppColors.success,
          ),
          const SizedBox(height: AppSpacing.md),
          _phaseTile(
            Icons.record_voice_over_rounded,
            'Pronunciation',
            '3 sentences to read aloud',
            AppColors.xp,
          ),
          const Spacer(),
          PrimaryButton(
            label: 'Start Assessment',
            gradient: true,
            icon: Icons.play_arrow_rounded,
            onPressed: _startAssessment,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Widget _phaseTile(IconData icon, String title, String subtitle, Color accent) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.title),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTextStyles.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrammarView() {
    final q = _currentQuestion;
    final total = _questionsForSkill(AssessmentSkill.grammar).length;
    final haveTranscript = _grammarTranscriptFinal.trim().isNotEmpty;
    final canSubmit = haveTranscript && !_isRecording;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _phaseHeading(Icons.edit_note_rounded, 'Grammar',
                    _indexWithinPhase + 1, total),
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(q.prompt, style: AppTextStyles.title),
                      if (q.instructions.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          q.instructions,
                          style: AppTextStyles.caption.copyWith(
                            fontStyle: FontStyle.italic,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  border: AppColors.border,
                  child: SizedBox(
                    height: 150,
                    child: SingleChildScrollView(
                      child: _grammarTranscriptFinal.isEmpty &&
                              _grammarTranscriptInterim.isEmpty
                          ? Text(
                              _isRecording
                                  ? 'Listening… start speaking.'
                                  : 'Tap the microphone and speak your answer.',
                              style: AppTextStyles.body.copyWith(
                                color: AppColors.textSecondary,
                                fontStyle: FontStyle.italic,
                              ),
                            )
                          : RichText(
                              text: TextSpan(
                                style:
                                    AppTextStyles.body.copyWith(fontSize: 16),
                                children: [
                                  TextSpan(text: _grammarTranscriptFinal),
                                  if (_grammarTranscriptInterim.isNotEmpty)
                                    TextSpan(
                                      text: _grammarTranscriptFinal.isEmpty
                                          ? _grammarTranscriptInterim
                                          : ' $_grammarTranscriptInterim',
                                      style: AppTextStyles.body.copyWith(
                                          color: AppColors.textSecondary),
                                    ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Center(
                  child: Column(
                    children: [
                      _buildMicButton(
                        isRecording: _isRecording,
                        onPressed: _isRecording
                            ? _stopGrammarRecording
                            : _startGrammarRecording,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _isRecording
                            ? 'Recording  •  ${_formatDuration(_recordedDuration)}'
                            : haveTranscript
                                ? 'Tap to re-record'
                                : 'Tap to start',
                        style: AppTextStyles.caption.copyWith(
                          color: _isRecording
                              ? AppColors.danger
                              : AppColors.textSecondary,
                        ),
                      ),
                      if (haveTranscript && !_isRecording) ...[
                        const SizedBox(height: AppSpacing.xs),
                        TextButton(
                          onPressed: _resetGrammarTranscript,
                          child: const Text(
                            'Clear',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
        // Pinned action bar — never gets pushed off-screen by content shifts
        // (e.g. the Clear button appearing after stop adds height).
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, AppSpacing.sm, AppSpacing.xl, AppSpacing.lg),
            child: PrimaryButton(
              label: _indexWithinPhase + 1 == total
                  ? 'Next section →'
                  : 'Next question',
              gradient: true,
              onPressed: canSubmit ? _submitGrammarAnswer : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAudioView() {
    final q = _currentQuestion;
    final isFluency = _phase == _Phase.fluency;
    final skill =
        isFluency ? AssessmentSkill.fluency : AssessmentSkill.pronunciation;
    final total = _questionsForSkill(skill).length;
    final minDuration = q.minDurationSeconds;
    final metMinimum = _recordedDuration.inSeconds >= minDuration;
    final haveRecording = _currentAudioPath != null && !_isRecording;
    final canSubmit = haveRecording && (isFluency ? metMinimum : true);
    final phaseLabel = isFluency ? 'Fluency' : 'Pronunciation';
    final phaseIcon = isFluency
        ? Icons.mic_external_on_rounded
        : Icons.record_voice_over_rounded;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _phaseHeading(
                    phaseIcon, phaseLabel, _indexWithinPhase + 1, total),
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(q.prompt, style: AppTextStyles.title),
                      if (q.instructions.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          q.instructions,
                          style: AppTextStyles.caption.copyWith(
                            fontStyle: FontStyle.italic,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      if (!isFluency && q.targetSentence != null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          decoration: BoxDecoration(
                            color:
                                AppColors.primary.withValues(alpha: 0.06),
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                            border: Border.all(
                              color: AppColors.primary
                                  .withValues(alpha: 0.2),
                            ),
                          ),
                          child: Text(
                            q.targetSentence!,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxxl),
                Center(
                  child: Column(
                    children: [
                      Text(
                        _formatDuration(_recordedDuration),
                        style: const TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          fontFeatures: [FontFeature.tabularFigures()],
                          letterSpacing: -1.2,
                        ),
                      ),
                      if (isFluency) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          metMinimum
                              ? '✓ Min ${minDuration}s reached'
                              : 'Min: ${minDuration}s',
                          style: AppTextStyles.caption.copyWith(
                            color: metMinimum
                                ? AppColors.success
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      _buildMicButton(
                        isRecording: _isRecording,
                        onPressed:
                            _isRecording ? _stopRecording : _startRecording,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _isRecording
                            ? 'Recording'
                            : haveRecording
                                ? 'Tap to re-record'
                                : 'Tap to start',
                        style: AppTextStyles.caption.copyWith(
                          color: _isRecording
                              ? AppColors.danger
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
        // Pinned action bar — same pattern as the grammar view.
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, AppSpacing.sm, AppSpacing.xl, AppSpacing.lg),
            child: PrimaryButton(
              label: _phase == _Phase.pronunciation &&
                      _indexWithinPhase + 1 == total
                  ? 'Submit assessment'
                  : _phase == _Phase.fluency &&
                          _indexWithinPhase + 1 == total
                      ? 'Next section →'
                      : 'Next question',
              gradient: true,
              onPressed: canSubmit
                  ? () => _submitAudioAnswer(_currentAudioPath!)
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  /// Big circular mic CTA. Pulses a soft red ring while recording.
  Widget _buildMicButton({
    required bool isRecording,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isRecording)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                final scale = 1.0 + 0.18 * _pulseController.value;
                return Container(
                  width: 96 * scale,
                  height: 96 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.danger.withValues(
                        alpha: 1.0 - _pulseController.value,
                      ),
                      width: 4,
                    ),
                  ),
                );
              },
            ),
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            elevation: 0,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isRecording
                      ? const LinearGradient(
                          colors: [AppColors.danger, Color(0xFFFF6B6B)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : const LinearGradient(
                          colors: [
                            AppColors.primary,
                            AppColors.primaryGradientEnd
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  boxShadow: [
                    BoxShadow(
                      color: (isRecording
                              ? AppColors.danger
                              : AppColors.primary)
                          .withValues(alpha: 0.4),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Per-section heading with phase icon and "X of Y" badge.
  Widget _phaseHeading(IconData icon, String label, int current, int total) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Icon(icon, color: AppColors.primary, size: 22),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.title),
              Text(
                'Question $current of $total',
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGradingView() {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 5,
            ),
          ),
          SizedBox(height: AppSpacing.xxl),
          Text('Grading your assessment…', style: AppTextStyles.display),
          SizedBox(height: AppSpacing.sm),
          Text(
            "This can take 30–60 seconds — we're running grammar, fluency, and pronunciation checks.",
            textAlign: TextAlign.center,
            style: AppTextStyles.body,
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
