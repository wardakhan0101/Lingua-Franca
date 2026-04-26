import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/analysis_storage_service.dart';
import '../theme/app_colors.dart';

class PronunciationReportScreen extends StatefulWidget {
  final Map<String, dynamic> pronunciationData;
  final String audioPath;
  final int earnedXp;
  // Shared session id for Firestore. Null when isHistorical = true.
  final String? sessionId;
  // When true, this is a past session re-opened from Profile — skip the
  // Firestore write so we don't duplicate the doc.
  final bool isHistorical;

  const PronunciationReportScreen({
    super.key,
    required this.pronunciationData,
    required this.audioPath,
    this.earnedXp = 0,
    this.sessionId,
    this.isHistorical = false,
  });

  @override
  State<PronunciationReportScreen> createState() =>
      _PronunciationReportScreenState();
}

class _PronunciationReportScreenState extends State<PronunciationReportScreen>
    with AutomaticKeepAliveClientMixin<PronunciationReportScreen> {
  final AudioPlayer _player = AudioPlayer();
  final AnalysisStorageService _storage = AnalysisStorageService();
  int? _expandedIndex;
  StreamSubscription? _positionSub;
  Duration? _stopAt;
  bool _storedOnce = false;

  static const Color _accent = AppColors.primary;
  static const Color _bg = AppColors.background;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadAudio();
    WidgetsBinding.instance.addPostFrameCallback((_) => _persistOnce());
  }

  Future<void> _loadAudio() async {
    if (widget.audioPath.isEmpty) return;
    final file = File(widget.audioPath);
    if (!await file.exists()) return;
    try {
      await _player.setFilePath(widget.audioPath);
      _positionSub = _player.positionStream.listen((pos) {
        final stop = _stopAt;
        if (stop != null && pos >= stop) {
          _player.pause();
          _stopAt = null;
        }
      });
    } catch (e) {
      debugPrint('Pronunciation audio load failed: $e');
    }
  }

  Future<void> _persistOnce() async {
    if (_storedOnce) return;
    _storedOnce = true;
    // Re-opening a past session from Profile — doc already exists.
    if (widget.isHistorical) return;
    if (widget.sessionId == null) {
      debugPrint('Pronunciation store skipped: no sessionId');
      return;
    }
    try {
      await _storage.storePronunciationAnalysis(
        sessionId: widget.sessionId!,
        pronunciationData: widget.pronunciationData,
        audioPath: widget.audioPath,
      );
    } catch (e) {
      debugPrint('storePronunciationAnalysis failed: $e');
    }
  }

  Future<void> _playSegment(double startSec, double endSec) async {
    final start = Duration(milliseconds: (startSec * 1000).round());
    final end = Duration(milliseconds: (endSec * 1000).round());
    _stopAt = end;
    await _player.seek(start);
    await _player.play();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Color _scoreColor(int? score) {
    if (score == null) return Colors.grey.shade400;
    if (score >= 85) return const Color(0xFF22C55E);
    if (score >= 50) return const Color(0xFFEAB308);
    return const Color(0xFFEF4444);
  }

  LinearGradient _scoreGradient(int score) {
    if (score >= 85) {
      return const LinearGradient(
        colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
      );
    }
    if (score >= 50) {
      return const LinearGradient(
        colors: [Color(0xFFFACC15), Color(0xFFF97316)],
      );
    }
    return const LinearGradient(
      colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final data = widget.pronunciationData;
    final overall = (data['overall_score'] as num?)?.toInt() ?? 0;
    final perWord = (data['per_word'] as List?) ?? const [];
    final accentLabel = data['detected_accent'] as String?;
    final accentConfidence =
        (data['accent_confidence'] as num?)?.toDouble() ?? 0.0;
    final accentEvidence = List<String>.from(
      (data['accent_evidence'] as List?) ?? const [],
    );

    return Scaffold(
      backgroundColor: _bg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _overallCard(overall, perWord.length),
            if (accentLabel != null) ...[
              const SizedBox(height: 16),
              _accentCard(accentLabel, accentConfidence, accentEvidence),
            ],
            const SizedBox(height: 16),
            _transcriptCard(perWord),
            const SizedBox(height: 16),
            if (widget.earnedXp > 0) _xpBadge(widget.earnedXp),
          ],
        ),
      ),
    );
  }

  static const Map<String, String> _accentDisplayName = {
    'american': 'American English',
    'british': 'British English',
    'pakistani': 'Pakistani English',
  };

  Widget _accentCard(String label, double confidence, List<String> evidence) {
    final displayName = _accentDisplayName[label] ?? label;
    final percent = (confidence * 100).round();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(Icons.record_voice_over, 'Detected accent'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: Colors.black87,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$percent% confidence',
                  style: const TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          if (evidence.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final bullet in evidence)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '•  ',
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    Expanded(
                      child: Text(
                        bullet,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _overallCard(int score, int wordCount) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: _scoreGradient(score),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.25),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$score',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 32,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pronunciation Score',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _scoreBlurb(score),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  '$wordCount words analyzed',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _scoreBlurb(int score) {
    if (score >= 85) return 'Excellent — clear articulation across the board.';
    if (score >= 70) return 'Good — a few phonemes to polish.';
    if (score >= 50) return 'Mixed — focus on the flagged phonemes below.';
    return 'Needs practice — tap flagged words to hear how they should sound.';
  }

  Widget _transcriptCard(List perWord) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(Icons.text_fields, 'Word-by-word'),
          const SizedBox(height: 12),
          if (perWord.isEmpty)
            const Text(
              'No words were analyzed.',
              style: TextStyle(color: Colors.grey),
            )
          else
            Column(
              children: [
                for (int i = 0; i < perWord.length; i++)
                  _wordRow(i, Map<String, dynamic>.from(perWord[i] as Map)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _wordRow(int idx, Map<String, dynamic> w) {
    final word = (w['word'] as String?) ?? '';
    final score = (w['score'] as num?)?.toInt();
    final issues = (w['issues'] as List?) ?? const [];
    final expected = List<String>.from(w['expected_phonemes'] as List? ?? const []);
    final actual = List<String>.from(w['actual_phonemes'] as List? ?? const []);
    final phonScores = List<int>.from(
      ((w['phoneme_scores'] as List?) ?? const []).map(
        (e) => (e as num).toInt(),
      ),
    );
    final start = (w['start'] as num?)?.toDouble();
    final end = (w['end'] as num?)?.toDouble();
    final skippedReason = w['skipped_reason'] as String?;
    final expanded = _expandedIndex == idx;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap:
                score == null && skippedReason != null
                    ? null
                    : () =>
                        setState(() => _expandedIndex = expanded ? null : idx),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _scoreColor(score),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          word,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color:
                                score == null
                                    ? Colors.grey
                                    : Colors.black87,
                            fontStyle:
                                score == null
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                          ),
                        ),
                        if (score == null && skippedReason != null)
                          Text(
                            skippedReason == 'too_short'
                                ? 'Skipped — too short to score'
                                : 'Skipped — unknown word',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (score != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _scoreColor(score).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$score',
                        style: TextStyle(
                          color: _scoreColor(score),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (score != null)
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.grey.shade500,
                    ),
                ],
              ),
            ),
          ),
          if (expanded)
            _wordDetail(expected, actual, phonScores, issues, start, end),
        ],
      ),
    );
  }

  Widget _wordDetail(
    List<String> expected,
    List<String> actual,
    List<int> scores,
    List issues,
    double? start,
    double? end,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'Expected:  ',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (int i = 0; i < expected.length; i++)
                      _phonemeChip(
                        expected[i],
                        i < scores.length ? scores[i] : null,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text(
                'You said:  ',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final p in actual)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          p,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (issues.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final issue in issues) _issueCard(Map<String, dynamic>.from(issue as Map)),
          ],
          if (start != null && end != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _playSegment(start, end),
                icon: const Icon(Icons.play_arrow, color: _accent),
                label: const Text(
                  'Play your recording',
                  style: TextStyle(color: _accent),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _phonemeChip(String p, int? score) {
    final color = _scoreColor(score);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        p,
        style: TextStyle(
          fontFamily: 'monospace',
          color: color.withOpacity(0.9),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _issueCard(Map<String, dynamic> issue) {
    final label = issue['expected_ipa_label'] as String? ?? '';
    final hint = issue['hint'] as String? ?? '';
    final expected = issue['expected'] as String? ?? '';
    final actual = issue['actual'] as String?;
    final type = issue['type'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            type == 'substitution'
                ? 'Swapped /$expected/ for /${actual ?? "?"}/'
                : 'Dropped /$expected/',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFFDC2626),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 4),
          Text(hint, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _xpBadge(int xp) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _accent.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '+$xp XP earned',
          style: const TextStyle(color: _accent, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _sectionHeading(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: _accent, size: 18),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ],
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.05),
        blurRadius: 5,
        offset: const Offset(0, 2),
      ),
    ],
  );
}
