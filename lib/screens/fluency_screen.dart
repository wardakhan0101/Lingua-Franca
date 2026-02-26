import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';import '../services/analysis_storage_service.dart';

class FluencyScreen extends StatefulWidget {
  final Map<String, dynamic> fluencyData;
  final String audioPath; // Path to the recorded user audio

  const FluencyScreen({super.key, required this.fluencyData, required this.audioPath});

  @override
  State<FluencyScreen> createState() => _FluencyScreenState();
}

class _FluencyScreenState extends State<FluencyScreen> with AutomaticKeepAliveClientMixin<FluencyScreen> {
  String _transcript = "";
  String _annotatedTranscript = ""; // contains markers
  List<Map<String, dynamic>> _fluencyIssues = [];
  List<Map<String, dynamic>> _detectedFillers = []; // [{word, start_time}]
  final AnalysisStorageService _storageService = AnalysisStorageService();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    debugPrint("=== FLUENCY SCREEN INITIALIZED ===");
    debugPrint("Audio path received: ${widget.audioPath}");
    _processFluencyData();
  }

  void _processFluencyData() {
    try {
      final data = widget.fluencyData;
      final transcriptText = data['transcript'] as String? ?? '';
      final annotatedText = data['annotated_transcript'] as String? ?? transcriptText;
      final issuesList = data['fluency_issues'] as List? ?? [];
      final fillersList = data['detected_fillers'] as List? ?? [];
      final stuttersList = data['stutters'] as List? ?? [];
      final pausesList = data['pauses'] as List? ?? [];
      final fastPhrasList = data['fast_phrases'] as List? ?? [];

      final issues = issuesList.map((issue) {
        return {
          'title': issue['title'] as String? ?? 'ISSUE',
          'errorText': issue['errorText'] as String? ?? '',
          'explanation': issue['explanation'] as String? ?? '',
          'suggestions': List<String>.from(issue['suggestions'] as List? ?? []),
        };
      }).toList();

      final fillers = fillersList.map((f) {
        return {
          'word': f['word'] as String? ?? '',
          'start_time': (f['start_time'] as num?)?.toDouble() ?? 0.0,
        };
      }).toList().cast<Map<String, dynamic>>();

      debugPrint("Total issues found: ${issues.length}");
      debugPrint("Transcript: $transcriptText");
      for (var issue in issues) {
        debugPrint("Issue detected: ${issue['title']} — ${issue['errorText']}");
      }
      debugPrint("Detected fillers: ${fillers.length}, Stutters: ${stuttersList.length}, Fast Phrases: ${fastPhrasList.length}, Pauses: ${pausesList.length}");

      setState(() {
        _transcript = transcriptText;
        _annotatedTranscript = annotatedText;
        _fluencyIssues = issues;
        _detectedFillers = fillers;
      });

      _storeAnalysisResults();
    } catch (e, stackTrace) {
      debugPrint("Error processing API response: $e");
      debugPrint("Stack trace: $stackTrace");
      setState(() {
        _transcript = "Error processing audio analysis.";
        // Reset the issues list on error so we don't accidentally show 'Excellent Fluency'
        _fluencyIssues = []; 
      });
    }
  }

  // Build a RichText that highlights detected filler words, pauses, stutters, and fast phrases.
  // Parses [F], [P-minor], [P-major], [S], and [FAST] markers from annotated_transcript.
  Widget _buildAnnotatedTranscript() {
    final text = _annotatedTranscript.isEmpty
        ? (_transcript.isEmpty ? "No speech detected." : _transcript)
        : _annotatedTranscript;

    if (!text.contains('[F]') && !text.contains('[P-minor]') && !text.contains('[P-major]') && !text.contains('[S]') && !text.contains('[FAST]')) {
      // No markers — plain text
      return Text(
        text.isEmpty ? "No speech detected." : text,
        style: const TextStyle(fontSize: 16, height: 1.6, color: Color(0xFF1F2937)),
      );
    }

    // Parse markers into RichText spans
    final spans = <InlineSpan>[];
    
    // We parse [FAST] tokens separately so they don't consume nested markers like [P-minor],
    // while keeping [F]...[/F] block captures intact.
    final marker = RegExp(r'\[(FAST)\]|\[(/FAST)\]|\[(F|P-minor|P-major|S)\](.*?)\[/\3\]');
    
    int cursor = 0;
    bool isFast = false;

    TextStyle getTextStyle(bool fast) {
      return TextStyle(
        fontSize: 16, 
        height: 1.6, 
        color: fast ? const Color(0xFF1D4ED8) : const Color(0xFF1F2937),
        backgroundColor: fast ? const Color(0xFFDBEAFE) : null,
        fontWeight: fast ? FontWeight.w600 : FontWeight.normal,
      );
    }

    for (final match in marker.allMatches(text)) {
      // Text before this marker
      if (match.start > cursor) {
        spans.add(TextSpan(
          text: text.substring(cursor, match.start),
          style: getTextStyle(isFast),
        ));
      }
      
      final fullMatch = match.group(0)!;
      if (fullMatch == '[FAST]') {
        isFast = true;
      } else if (fullMatch == '[/FAST]') {
        isFast = false;
      } else {
        final tag = match.group(3);
        final content = match.group(4) ?? '';
        
        if (tag == 'F') {
          // Filler word — amber
          spans.add(TextSpan(
            text: content,
            style: const TextStyle(
              color: Color(0xFFD97706),       // amber-600
              fontWeight: FontWeight.w700,
              fontSize: 16,
              height: 1.6,
              backgroundColor: Color(0xFFFEF3C7), // amber-100 bg
            ),
          ));
        } else if (tag == 'S') {
          // Stuttered word — purple
          spans.add(TextSpan(
            text: content,
            style: const TextStyle(
              color: Color(0xFF7E22CE),       // purple-700
              fontWeight: FontWeight.w700,
              fontSize: 16,
              height: 1.6,
              backgroundColor: Color(0xFFF3E8FF), // purple-100 bg
            ),
          ));
        } else if (tag == 'P-minor' || tag == 'P-major') {
          // Pause marker - styled as a small chip inside the text
          final isMajor = tag == 'P-major';
          final bgColor = isMajor ? const Color(0xFFFEE2E2) : Colors.grey.shade200;
          final borderColor = isMajor ? const Color(0xFFFCA5A5) : Colors.grey.shade300;
          final textColor = isMajor ? const Color(0xFFDC2626) : Colors.grey.shade600;
          final icon = isMajor ? Icons.warning_amber_rounded : Icons.timer_outlined;

          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: textColor),
                  const SizedBox(width: 4),
                  Text(
                    content,
                    style: TextStyle(
                      fontSize: 12,
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ));
        }
      }
      
      cursor = match.end;
    }

    // Remaining text after last marker
    if (cursor < text.length) {
      spans.add(TextSpan(
        text: text.substring(cursor),
        style: getTextStyle(isFast),
      ));
    }

    return RichText(text: TextSpan(children: spans));
  }

  // Store the analysis results in Firebase
  Future<void> _storeAnalysisResults() async {
    try {
      await _storageService.storeFluencyAnalysis(
        transcript: _transcript,
        fluencyIssues: _fluencyIssues,
        audioPath: widget.audioPath,
      );
    } catch (e) {
      debugPrint("Failed to store fluency analysis in Firebase: $e");
      // Don't show error to user, just log it
    }
  }

  // --- UI SECTION ---

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        title: const Text(
          'Fluency Report',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        automaticallyImplyLeading: false, // UnifiedReportScreen handles the back button
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Transcript Section
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9FAFB),
                              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(20),
                                topRight: Radius.circular(20),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.record_voice_over_rounded, size: 16, color: Colors.grey[600]),
                                const SizedBox(width: 8),
                                Text(
                                  "TRANSCRIPT ANALYSIS",
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: _buildAnnotatedTranscript(),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // 2. Header for Issues
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Areas for Improvement",
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6C63FF).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.2)),
                          ),
                          child: Text(
                            "${_fluencyIssues.length} Found",
                            style: const TextStyle(
                              color: Color(0xFF6C63FF),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 3. Dynamic Mistake Cards
                    if (_fluencyIssues.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(32),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.verified_rounded, size: 64, color: Color(0xFF34D399)),
                            SizedBox(height: 16),
                            Text(
                              "Excellent Fluency!",
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                            ),
                            SizedBox(height: 8),
                            Text(
                              "No major issues detected. Keep up the great work!",
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._fluencyIssues.map((issue) => Column(
                        children: [
                          _buildFluencyCard(
                            title: issue['title'],
                            errorText: issue['errorText'],
                            explanation: issue['explanation'],
                            suggestions: issue['suggestions'],
                          ),
                          const SizedBox(height: 16),
                        ],
                      )),

                    const SizedBox(height: 40),
                  ],
                ),
      ),
    );
  }

  Widget _buildFluencyCard({
    required String title,
    required String errorText,
    required String explanation,
    required List<String> suggestions,
  }) {
    // Define an icon based on title for extra polish
    IconData icon;
    Color accentColor;

    if (title.contains("SPEED") || title.contains("RUSHED")) {
      icon = Icons.speed_rounded;
      accentColor = const Color(0xFF3B82F6); // Blue
    } else if (title.contains("PAUSE") || title.contains("HESITATION")) {
      icon = Icons.timer_off_outlined;
      accentColor = const Color(0xFFF59E0B); // Amber
    } else if (title.contains("STUTTERING") || title.contains("REPETITION")) {
      icon = Icons.loop_rounded;
      accentColor = const Color(0xFF8B5CF6); // Purple
    } else if (title.contains("FILLER")) {
      icon = Icons.graphic_eq_rounded;
      accentColor = const Color(0xFFEF4444); // Red
    } else {
      icon = Icons.info_outline_rounded;
      accentColor = const Color(0xFF6B7280); // Gray
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Error Highlight Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accentColor.withValues(alpha: 0.1)),
            ),
            child: Text(
              errorText,
              style: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16
              ),
            ),
          ),

          const SizedBox(height: 12),

          Text(
            explanation,
            style: const TextStyle(color: Color(0xFF4B5563), fontSize: 14, height: 1.5),
          ),

          const SizedBox(height: 16),

          const Text(
            "SUGGESTIONS",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              color: Color(0xFF9CA3AF),
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),

          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: suggestions.map((suggestion) {
              return Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 80),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 14),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        suggestion,
                        style: const TextStyle(
                            color: Color(0xFF374151),
                            fontSize: 12,
                            fontWeight: FontWeight.w600
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}