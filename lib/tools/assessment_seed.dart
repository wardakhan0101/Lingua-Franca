// One-off tool to seed the Firestore `assessment_questions` collection with
// starter content — 5 questions per (skill × level) pool = 60 total.
//
// Run it once from a dev screen using [AssessmentSeedScreen], or call
// [runAssessmentSeed] directly from anywhere with a signed-in Firebase
// user. After seeding, questions can be edited/added/removed from the
// Firebase console without redeploying the app.
//
// Safe to re-run: uses [merge] writes with deterministic doc IDs so it
// overwrites existing seeds without creating duplicates.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Starter question pool. Each map is one Firestore doc in
/// `assessment_questions/{autoId}`. The `id` key is consumed as the doc ID
/// (so re-seeding overwrites, doesn't duplicate) and not stored as a field.
const List<Map<String, dynamic>> kSeedQuestions = [
  // =====================================================================
  // GRAMMAR — BEGINNER  (present×2, past×1, future×1, open×1)
  // =====================================================================
  {
    'id': 'grammar_beginner_01',
    'skill': 'grammar',
    'level': 'beginner',
    'prompt': 'What do you usually do on weekends?',
    'instructions': 'Use the present tense.',
    'requiredTense': 'present_simple',
  },
  {
    'id': 'grammar_beginner_02',
    'skill': 'grammar',
    'level': 'beginner',
    'prompt': 'Describe your family members briefly.',
    'instructions': 'Use the present tense.',
    'requiredTense': 'present_simple',
  },
  {
    'id': 'grammar_beginner_03',
    'skill': 'grammar',
    'level': 'beginner',
    'prompt': 'What did you have for breakfast today?',
    'instructions': 'Answer in the past tense.',
    'requiredTense': 'past_simple',
  },
  {
    'id': 'grammar_beginner_04',
    'skill': 'grammar',
    'level': 'beginner',
    'prompt': 'What will you do this evening after you finish practicing?',
    'instructions': "Use the future tense ('will' + verb).",
    'requiredTense': 'future_simple',
  },
  {
    'id': 'grammar_beginner_05',
    'skill': 'grammar',
    'level': 'beginner',
    'prompt': 'Tell me about a hobby you enjoy.',
    'instructions': 'Speak naturally for 2–3 sentences.',
  },

  // =====================================================================
  // GRAMMAR — INTERMEDIATE  (one per tense: past_simple, past_perfect,
  // present_simple, present_perfect, future_simple)
  // =====================================================================
  {
    'id': 'grammar_intermediate_01',
    'skill': 'grammar',
    'level': 'intermediate',
    'prompt': 'Describe what you usually do during a typical work or school week.',
    'instructions': 'Use the present tense.',
    'requiredTense': 'present_simple',
  },
  {
    'id': 'grammar_intermediate_02',
    'skill': 'grammar',
    'level': 'intermediate',
    'prompt': 'Tell me about something memorable that happened to you last month.',
    'instructions': 'Answer in the past tense.',
    'requiredTense': 'past_simple',
  },
  {
    'id': 'grammar_intermediate_03',
    'skill': 'grammar',
    'level': 'intermediate',
    'prompt': "What have you learned recently that you didn't know before?",
    'instructions': 'Use the present perfect (have/has + past participle).',
    'requiredTense': 'present_perfect',
  },
  {
    'id': 'grammar_intermediate_04',
    'skill': 'grammar',
    'level': 'intermediate',
    'prompt':
        'Describe something you had already accomplished before you turned fifteen.',
    'instructions': 'Use the past perfect (had + past participle).',
    'requiredTense': 'past_perfect',
  },
  {
    'id': 'grammar_intermediate_05',
    'skill': 'grammar',
    'level': 'intermediate',
    'prompt': 'What will you do differently next year and why?',
    'instructions': "Use the future tense ('will' + verb).",
    'requiredTense': 'future_simple',
  },

  // =====================================================================
  // GRAMMAR — ADVANCED  (one per tense)
  // =====================================================================
  {
    'id': 'grammar_advanced_01',
    'skill': 'grammar',
    'level': 'advanced',
    'prompt':
        'Explain how you generally approach solving difficult problems at work or school.',
    'instructions': 'Use the present tense.',
    'requiredTense': 'present_simple',
  },
  {
    'id': 'grammar_advanced_02',
    'skill': 'grammar',
    'level': 'advanced',
    'prompt':
        'Describe a time when you had to make a difficult choice quickly.',
    'instructions': 'Use the past tense.',
    'requiredTense': 'past_simple',
  },
  {
    'id': 'grammar_advanced_03',
    'skill': 'grammar',
    'level': 'advanced',
    'prompt':
        'What have you gained from an experience that challenged you?',
    'instructions': 'Use the present perfect.',
    'requiredTense': 'present_perfect',
  },
  {
    'id': 'grammar_advanced_04',
    'skill': 'grammar',
    'level': 'advanced',
    'prompt':
        'By the time you finished school, what had you already decided about your future?',
    'instructions': 'Use the past perfect.',
    'requiredTense': 'past_perfect',
  },
  {
    'id': 'grammar_advanced_05',
    'skill': 'grammar',
    'level': 'advanced',
    'prompt':
        'How will your professional life look three years from now?',
    'instructions': 'Use the future tense.',
    'requiredTense': 'future_simple',
  },

  // =====================================================================
  // GRAMMAR — FLUENT  (one per tense)
  // =====================================================================
  {
    'id': 'grammar_fluent_01',
    'skill': 'grammar',
    'level': 'fluent',
    'prompt': 'Describe the principles that guide your decision-making.',
    'instructions': 'Use the present tense.',
    'requiredTense': 'present_simple',
  },
  {
    'id': 'grammar_fluent_02',
    'skill': 'grammar',
    'level': 'fluent',
    'prompt':
        'Describe a pivotal moment that shaped your current perspective.',
    'instructions': 'Use the past tense.',
    'requiredTense': 'past_simple',
  },
  {
    'id': 'grammar_fluent_03',
    'skill': 'grammar',
    'level': 'fluent',
    'prompt': 'Discuss a cause or idea you have championed over time.',
    'instructions': 'Use the present perfect.',
    'requiredTense': 'present_perfect',
  },
  {
    'id': 'grammar_fluent_04',
    'skill': 'grammar',
    'level': 'fluent',
    'prompt':
        'Describe a situation where your assumptions had already failed you before you adapted.',
    'instructions': 'Use the past perfect.',
    'requiredTense': 'past_perfect',
  },
  {
    'id': 'grammar_fluent_05',
    'skill': 'grammar',
    'level': 'fluent',
    'prompt':
        'How will you measure success in your life over the next decade?',
    'instructions': 'Use the future tense.',
    'requiredTense': 'future_simple',
  },

  // =====================================================================
  // FLUENCY — BEGINNER (30 s)
  // =====================================================================
  {
    'id': 'fluency_beginner_01',
    'skill': 'fluency',
    'level': 'beginner',
    'prompt': 'Tell me about your family.',
    'instructions': 'Speak for at least 15 seconds.',
    'minDurationSeconds': 15,
  },
  {
    'id': 'fluency_beginner_02',
    'skill': 'fluency',
    'level': 'beginner',
    'prompt': 'Describe where you live.',
    'instructions': 'Speak for at least 15 seconds.',
    'minDurationSeconds': 15,
  },
  {
    'id': 'fluency_beginner_03',
    'skill': 'fluency',
    'level': 'beginner',
    'prompt': "What is your favorite hobby? Explain why you enjoy it.",
    'instructions': 'Speak for at least 15 seconds.',
    'minDurationSeconds': 15,
  },
  {
    'id': 'fluency_beginner_04',
    'skill': 'fluency',
    'level': 'beginner',
    'prompt': 'Describe a typical school or work day for you.',
    'instructions': 'Speak for at least 15 seconds.',
    'minDurationSeconds': 15,
  },
  {
    'id': 'fluency_beginner_05',
    'skill': 'fluency',
    'level': 'beginner',
    'prompt': 'Tell me about a food you love and how it is usually prepared.',
    'instructions': 'Speak for at least 15 seconds.',
    'minDurationSeconds': 15,
  },

  // =====================================================================
  // FLUENCY — INTERMEDIATE (45 s)
  // =====================================================================
  {
    'id': 'fluency_intermediate_01',
    'skill': 'fluency',
    'level': 'intermediate',
    'prompt': 'Describe a place you would love to visit and explain why.',
    'instructions': 'Speak for at least 17 seconds.',
    'minDurationSeconds': 17,
  },
  {
    'id': 'fluency_intermediate_02',
    'skill': 'fluency',
    'level': 'intermediate',
    'prompt': 'Tell me about a memorable experience from your childhood.',
    'instructions': 'Speak for at least 17 seconds.',
    'minDurationSeconds': 17,
  },
  {
    'id': 'fluency_intermediate_03',
    'skill': 'fluency',
    'level': 'intermediate',
    'prompt':
        'What is a book, movie, or show you recently enjoyed? Explain what you liked about it.',
    'instructions': 'Speak for at least 17 seconds.',
    'minDurationSeconds': 17,
  },
  {
    'id': 'fluency_intermediate_04',
    'skill': 'fluency',
    'level': 'intermediate',
    'prompt': 'Describe your dream job and what a typical day in it would look like.',
    'instructions': 'Speak for at least 17 seconds.',
    'minDurationSeconds': 17,
  },
  {
    'id': 'fluency_intermediate_05',
    'skill': 'fluency',
    'level': 'intermediate',
    'prompt': 'Tell me about a time you learned something new and how it went.',
    'instructions': 'Speak for at least 17 seconds.',
    'minDurationSeconds': 17,
  },

  // =====================================================================
  // FLUENCY — ADVANCED (60 s)
  // =====================================================================
  {
    'id': 'fluency_advanced_01',
    'skill': 'fluency',
    'level': 'advanced',
    'prompt': 'What is a social issue you care about? Explain your perspective.',
    'instructions': 'Speak for at least 20 seconds.',
    'minDurationSeconds': 20,
  },
  {
    'id': 'fluency_advanced_02',
    'skill': 'fluency',
    'level': 'advanced',
    'prompt':
        'Discuss the impact of technology on human relationships over the last decade.',
    'instructions': 'Speak for at least 20 seconds.',
    'minDurationSeconds': 20,
  },
  {
    'id': 'fluency_advanced_03',
    'skill': 'fluency',
    'level': 'advanced',
    'prompt':
        'Describe a person who has had a major influence on you and explain why.',
    'instructions': 'Speak for at least 20 seconds.',
    'minDurationSeconds': 20,
  },
  {
    'id': 'fluency_advanced_04',
    'skill': 'fluency',
    'level': 'advanced',
    'prompt':
        "What is a difficult decision you've had to make? How did you approach it?",
    'instructions': 'Speak for at least 20 seconds.',
    'minDurationSeconds': 20,
  },
  {
    'id': 'fluency_advanced_05',
    'skill': 'fluency',
    'level': 'advanced',
    'prompt': 'Explain an opinion you hold strongly and the reasoning behind it.',
    'instructions': 'Speak for at least 20 seconds.',
    'minDurationSeconds': 20,
  },

  // =====================================================================
  // FLUENCY — FLUENT (90 s)
  // =====================================================================
  {
    'id': 'fluency_fluent_01',
    'skill': 'fluency',
    'level': 'fluent',
    'prompt':
        "Compare two different career paths you've considered, with detailed reasoning about each.",
    'instructions': 'Speak for at least 20 seconds.',
    'minDurationSeconds': 20,
  },
  {
    'id': 'fluency_fluent_02',
    'skill': 'fluency',
    'level': 'fluent',
    'prompt':
        'Analyze a current global issue and propose a realistic solution.',
    'instructions': 'Speak for at least 20 seconds.',
    'minDurationSeconds': 20,
  },
  {
    'id': 'fluency_fluent_03',
    'skill': 'fluency',
    'level': 'fluent',
    'prompt':
        'Describe a philosophical question that fascinates you and explore multiple perspectives on it.',
    'instructions': 'Speak for at least 20 seconds.',
    'minDurationSeconds': 20,
  },
  {
    'id': 'fluency_fluent_04',
    'skill': 'fluency',
    'level': 'fluent',
    'prompt':
        'Discuss how one historical event has shaped the present world, in depth.',
    'instructions': 'Speak for at least 20 seconds.',
    'minDurationSeconds': 20,
  },
  {
    'id': 'fluency_fluent_05',
    'skill': 'fluency',
    'level': 'fluent',
    'prompt':
        'Explain a complex topic from your field of expertise to someone unfamiliar with it.',
    'instructions': 'Speak for at least 20 seconds.',
    'minDurationSeconds': 20,
  },

  // =====================================================================
  // PRONUNCIATION — BEGINNER  (short, natural, common phonemes)
  // =====================================================================
  {
    'id': 'pronunciation_beginner_01',
    'skill': 'pronunciation',
    'level': 'beginner',
    'prompt': 'Read this sentence aloud clearly.',
    'targetSentence':
        'The little girl carefully carried the small red basket.',
  },
  {
    'id': 'pronunciation_beginner_02',
    'skill': 'pronunciation',
    'level': 'beginner',
    'prompt': 'Read this sentence aloud clearly.',
    'targetSentence':
        'My brother bought fresh vegetables at the market this morning.',
  },
  {
    'id': 'pronunciation_beginner_03',
    'skill': 'pronunciation',
    'level': 'beginner',
    'prompt': 'Read this sentence aloud clearly.',
    'targetSentence':
        'She smiled at the tall boy holding a blue umbrella.',
  },
  {
    'id': 'pronunciation_beginner_04',
    'skill': 'pronunciation',
    'level': 'beginner',
    'prompt': 'Read this sentence aloud clearly.',
    'targetSentence':
        'We often drink hot tea and eat cookies in the afternoon.',
  },
  {
    'id': 'pronunciation_beginner_05',
    'skill': 'pronunciation',
    'level': 'beginner',
    'prompt': 'Read this sentence aloud clearly.',
    'targetSentence':
        'The friendly dog ran quickly across the quiet park.',
  },

  // =====================================================================
  // PRONUNCIATION — INTERMEDIATE  (natural sentences with TH / R / S clusters)
  // =====================================================================
  {
    'id': 'pronunciation_intermediate_01',
    'skill': 'pronunciation',
    'level': 'intermediate',
    'prompt': 'Read this sentence aloud clearly.',
    'targetSentence':
        'The thirsty traveler thought the three tall trees looked beautiful.',
  },
  {
    'id': 'pronunciation_intermediate_02',
    'skill': 'pronunciation',
    'level': 'intermediate',
    'prompt': 'Read this sentence aloud clearly.',
    'targetSentence':
        'She searched thoroughly through the shelves before finding the book.',
  },
  {
    'id': 'pronunciation_intermediate_03',
    'skill': 'pronunciation',
    'level': 'intermediate',
    'prompt': 'Read this sentence aloud clearly.',
    'targetSentence':
        "Thursday's thunderstorm thoroughly soaked the old wooden roof.",
  },
  {
    'id': 'pronunciation_intermediate_04',
    'skill': 'pronunciation',
    'level': 'intermediate',
    'prompt': 'Read this sentence aloud clearly.',
    'targetSentence':
        'The careful carpenter crafted a comfortable chair from curved oak.',
  },
  {
    'id': 'pronunciation_intermediate_05',
    'skill': 'pronunciation',
    'level': 'intermediate',
    'prompt': 'Read this sentence aloud clearly.',
    'targetSentence':
        'A red lorry and a yellow lorry rolled through the little village.',
  },

  // =====================================================================
  // PRONUNCIATION — ADVANCED  (longer natural sentences, academic vocabulary)
  // =====================================================================
  {
    'id': 'pronunciation_advanced_01',
    'skill': 'pronunciation',
    'level': 'advanced',
    'prompt': 'Read this sentence aloud clearly.',
    'targetSentence':
        'The thorough entrepreneur regularly scheduled meetings with the rural librarian.',
  },
  {
    'id': 'pronunciation_advanced_02',
    'skill': 'pronunciation',
    'level': 'advanced',
    'prompt': 'Read this sentence aloud clearly.',
    'targetSentence':
        'Researchers categorized the unusual phenomenon before presenting their findings to colleagues.',
  },
  {
    'id': 'pronunciation_advanced_03',
    'skill': 'pronunciation',
    'level': 'advanced',
    'prompt': 'Read this sentence aloud clearly.',
    'targetSentence':
        'The philosophical professor thoroughly explained the theoretical framework to her students.',
  },
  {
    'id': 'pronunciation_advanced_04',
    'skill': 'pronunciation',
    'level': 'advanced',
    'prompt': 'Read this sentence aloud clearly.',
    'targetSentence':
        'Infrastructure development requires sophisticated engineering strategies and careful financial planning.',
  },
  {
    'id': 'pronunciation_advanced_05',
    'skill': 'pronunciation',
    'level': 'advanced',
    'prompt': 'Read this sentence aloud clearly.',
    'targetSentence':
        'Environmentalists emphasized the irreversible consequences of unregulated industrial expansion.',
  },

  // =====================================================================
  // PRONUNCIATION — FLUENT  (natural professional/literary vocabulary)
  // =====================================================================
  {
    'id': 'pronunciation_fluent_01',
    'skill': 'pronunciation',
    'level': 'fluent',
    'prompt': 'Read this sentence aloud clearly.',
    'targetSentence':
        "The neuroscientist's detailed presentation illuminated the phenomenon for her colleagues.",
  },
  {
    'id': 'pronunciation_fluent_02',
    'skill': 'pronunciation',
    'level': 'fluent',
    'prompt': 'Read this sentence aloud clearly.',
    'targetSentence':
        'Architects occasionally encounter unexpected challenges when renovating historic buildings.',
  },
  {
    'id': 'pronunciation_fluent_03',
    'skill': 'pronunciation',
    'level': 'fluent',
    'prompt': 'Read this sentence aloud clearly.',
    'targetSentence':
        "Anthropologists meticulously documented the indigenous community's extraordinary traditions.",
  },
  {
    'id': 'pronunciation_fluent_04',
    'skill': 'pronunciation',
    'level': 'fluent',
    'prompt': 'Read this sentence aloud clearly.',
    'targetSentence':
        "Pharmaceutical researchers rigorously evaluated the drug's therapeutic potential and adverse reactions.",
  },
  {
    'id': 'pronunciation_fluent_05',
    'skill': 'pronunciation',
    'level': 'fluent',
    'prompt': 'Read this sentence aloud clearly.',
    'targetSentence':
        "The judiciary scrutinized the legislature's controversial interpretation of constitutional precedent.",
  },
];

/// Uploads every entry in [kSeedQuestions] to Firestore. Uses the `id` key
/// as the doc ID with `SetOptions(merge: true)` so re-running this overwrites
/// the existing seeds instead of creating duplicates. The `active` field
/// defaults to true unless explicitly set to false.
///
/// Returns the count of docs written. Throws if Firestore is unreachable or
/// the user isn't signed in (Firestore rules likely require auth).
Future<int> runAssessmentSeed({FirebaseFirestore? firestore}) async {
  final fs = firestore ?? FirebaseFirestore.instance;
  final col = fs.collection('assessment_questions');

  int written = 0;
  for (final q in kSeedQuestions) {
    final id = q['id'] as String;
    final data = Map<String, dynamic>.from(q)..remove('id');
    data.putIfAbsent('active', () => true);
    data['seededAt'] = FieldValue.serverTimestamp();
    await col.doc(id).set(data, SetOptions(merge: true));
    written++;
  }
  return written;
}

/// Drop this screen into [DevelopersScreen] (or push it from anywhere) to
/// run the seed with a tap. Shows progress and the final count.
class AssessmentSeedScreen extends StatefulWidget {
  const AssessmentSeedScreen({super.key});

  @override
  State<AssessmentSeedScreen> createState() => _AssessmentSeedScreenState();
}

class _AssessmentSeedScreenState extends State<AssessmentSeedScreen> {
  bool _running = false;
  String _status = 'Ready to seed ${kSeedQuestions.length} questions.';

  Future<void> _runSeed() async {
    setState(() {
      _running = true;
      _status = 'Uploading ${kSeedQuestions.length} questions...';
    });
    try {
      final count = await runAssessmentSeed();
      if (!mounted) return;
      setState(() {
        _status = 'Done — $count questions written to Firestore.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Failed: $e';
      });
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seed Assessment Questions')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _status,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _running ? null : _runSeed,
              child: _running
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Upload all 60 questions'),
            ),
          ],
        ),
      ),
    );
  }
}
