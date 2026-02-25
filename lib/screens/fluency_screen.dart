import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../services/analysis_storage_service.dart';

class FluencyScreen extends StatefulWidget {
  final String audioPath; // Path to the recorded user audio

  const FluencyScreen({super.key, required this.audioPath});

  @override
  State<FluencyScreen> createState() => _FluencyScreenState();
}

class _FluencyScreenState extends State<FluencyScreen> {
  bool _isLoading = true;
  String _transcript = "";
  String _annotatedTranscript = ""; // contains [F]...[/F] markers
  List<Map<String, dynamic>> _fluencyIssues = [];
  List<Map<String, dynamic>> _detectedFillers = []; // [{word, start_time}]
  final AnalysisStorageService _storageService = AnalysisStorageService();

  final String? _apiUrl = dotenv.env['FLUENCY_API_URL'];

  @override
  void initState() {
    super.initState();
    debugPrint("=== FLUENCY SCREEN INITIALIZED ===");
    debugPrint("Audio path received: ${widget.audioPath}");
    _analyzeFluency();
  }

  Future<void> _analyzeFluency() async {
    debugPrint("=== STARTING FLUENCY ANALYSIS ===");

    if (_apiUrl == null || _apiUrl!.isEmpty) {
      setState(() {
        _transcript = "Error: FLUENCY_API_URL is not set in .env";
        _isLoading = false;
      });
      return;
    }

    final url = Uri.parse('$_apiUrl/analyze');

    try {
      final audioFile = File(widget.audioPath);
      final exists = await audioFile.exists();
      debugPrint("File exists: $exists");

      if (!exists) {
        throw Exception("Audio file not found at: ${widget.audioPath}");
      }

      final audioBytes = await audioFile.readAsBytes();
      debugPrint("Audio file size: ${audioBytes.length} bytes");

      if (audioBytes.length <= 44) {
        throw Exception("Audio file is empty or invalid (only ${audioBytes.length} bytes)");
      }

      // Send as multipart/form-data to our Python API
      debugPrint("Sending request to Fluency Engine API...");
      final request = http.MultipartRequest('POST', url);
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        audioBytes,
        filename: 'recording.wav',
        contentType: MediaType('audio', 'wav'),
      ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint("Fluency API response status: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint("Fluency API response received");
        _processApiResponse(data);
      } else {
        debugPrint("Fluency API error: ${response.body}");
        throw Exception('Failed to analyze audio: ${response.statusCode} - ${response.body}');
      }
    } catch (e, stackTrace) {
      debugPrint("=== ERROR IN FLUENCY ANALYSIS ===");
      debugPrint("Error: $e");
      debugPrint("Stack trace: $stackTrace");
      setState(() {
        _transcript = "Error analyzing audio: $e\n\nPlease try again.";
        _isLoading = false;
      });
    }
  }

  void _processApiResponse(Map<String, dynamic> data) {
    try {
      final transcriptText = data['transcript'] as String? ?? '';
      final annotatedText = data['annotated_transcript'] as String? ?? transcriptText;
      final issuesList = data['fluency_issues'] as List? ?? [];
      final fillersList = data['detected_fillers'] as List? ?? [];

      final issues = issuesList.map((issue) {
        return {
          'title': issue['title'] as String,
          'errorText': issue['errorText'] as String,
          'explanation': issue['explanation'] as String,
          'suggestions': List<String>.from(issue['suggestions'] as List),
        };
      }).toList();

      final fillers = fillersList.map((f) {
        return {
          'word': f['word'] as String,
          'start_time': (f['start_time'] as num).toDouble(),
        };
      }).toList().cast<Map<String, dynamic>>();

      debugPrint("Total issues found: ${issues.length}");
      debugPrint("Transcript: $transcriptText");
      for (var issue in issues) {
        debugPrint("Issue detected: ${issue['title']} — ${issue['errorText']}");
      }
      debugPrint("Detected fillers: ${fillers.map((f) => '${f['word']}@${f['start_time'].toStringAsFixed(1)}s').join(', ')}");

      setState(() {
        _transcript = transcriptText;
        _annotatedTranscript = annotatedText;
        _fluencyIssues = issues;
        _detectedFillers = fillers;
        _isLoading = false;
      });

      _storeAnalysisResults();
    } catch (e, stackTrace) {
      debugPrint("Error processing API response: $e");
      debugPrint("Stack trace: $stackTrace");
      setState(() {
        _transcript = "Error processing audio analysis.";
        _isLoading = false;
      });
    }
  }

  // Build a RichText that highlights detected filler words in amber/orange,
  // and displays detected long pauses as grey pills.
  // Parses [F]...[/F] and [P]...[/P] markers from annotated_transcript.
  Widget _buildAnnotatedTranscript() {
    final text = _annotatedTranscript.isEmpty
        ? (_transcript.isEmpty ? "No speech detected." : _transcript)
        : _annotatedTranscript;

    if (!text.contains('[F]') && !text.contains('[P]')) {
      // No fillers or pauses — plain text
      return Text(
        text.isEmpty ? "No speech detected." : text,
        style: const TextStyle(fontSize: 16, height: 1.6, color: Color(0xFF1F2937)),
      );
    }

    // Parse markers into RichText spans
    final spans = <InlineSpan>[];
    // This regex matches either [F]content[/F] or [P]content[/P]
    final marker = RegExp(r'\[(F|P)\](.*?)\[/\1\]');
    int cursor = 0;

    for (final match in marker.allMatches(text)) {
      // Text before this marker
      if (match.start > cursor) {
        spans.add(TextSpan(
          text: text.substring(cursor, match.start),
          style: const TextStyle(
            fontSize: 16, height: 1.6, color: Color(0xFF1F2937),
          ),
        ));
      }
      
      final tag = match.group(1);
      final content = match.group(2) ?? '';
      
      if (tag == 'F') {
        // The filler word itself — highlighted
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
      } else if (tag == 'P') {
        // The pause marker - styled as a small chip inside the text
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer_outlined, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  content,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ));
      }
      
      cursor = match.end;
    }

    // Remaining text after last marker
    if (cursor < text.length) {
      spans.add(TextSpan(
        text: text.substring(cursor),
        style: const TextStyle(
          fontSize: 16, height: 1.6, color: Color(0xFF1F2937),
        ),
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
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: const Text(
          'Fluency Report',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          // Lingua Franca Theme Gradient
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF4FACFE), // Login Light Blue
              Color(0xFF8A4FFF), // Login Purple
            ],
          ),
        ),
        child: Stack(
          children: [
            // Decorative Background Circle
            Positioned(
              top: -100,
              right: -50,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
            ),

            // Content
            SafeArea(
              child: _isLoading
                  ? Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF8A4FFF)),
                      SizedBox(height: 16),
                      Text("Analyzing Fluency...", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF8A4FFF))),
                    ],
                  ),
                ),
              )
                  : SingleChildScrollView(
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
                              color: Colors.white
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            "${_fluencyIssues.length} Found",
                            style: const TextStyle(
                              color: Colors.white,
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
            ),
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

    if (title.contains("SPEED")) {
      icon = Icons.speed_rounded;
      accentColor = const Color(0xFF3B82F6); // Blue
    } else if (title.contains("PACING")) {
      icon = Icons.timer_off_outlined;
      accentColor = const Color(0xFFF59E0B); // Amber
    } else if (title.contains("FILLER")) {
      icon = Icons.graphic_eq_rounded;
      accentColor = const Color(0xFFEF4444); // Red
    } else {
      icon = Icons.loop_rounded;
      accentColor = const Color(0xFF8B5CF6); // Purple
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
                    Text(
                      suggestion,
                      style: const TextStyle(
                          color: Color(0xFF374151),
                          fontSize: 12,
                          fontWeight: FontWeight.w600
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