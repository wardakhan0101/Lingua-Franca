
void main() {
  print('Testing Streak Logic...');

  void test(String label, DateTime now, DateTime? lastActive, int currentStreak, int expectedStreak) {
    int result;
    if (lastActive == null) {
      result = 1;
    } else {
      // Normalize to UTC dates to compare days accurately
      DateTime today = DateTime(now.year, now.month, now.day);
      DateTime lastDay = DateTime(lastActive.year, lastActive.month, lastActive.day);
      
      int differenceInDays = today.difference(lastDay).inDays;

      if (differenceInDays == 1) {
        result = currentStreak + 1;
      } else if (differenceInDays > 1) {
        result = 1;
      } else {
        // differenceInDays is 0 (same day) or negative (shouldn't happen)
        result = currentStreak;
      }
    }

    if (result == expectedStreak) {
      print('✅ PASS: $label (Expected: $expectedStreak, Got: $result)');
    } else {
      print('❌ FAIL: $label (Expected: $expectedStreak, Got: $result)');
    }
  }

  // Monday 10 PM
  final mon10PM = DateTime(2026, 3, 9, 22, 0);
  // Tuesday 8 AM (Less than 24h)
  final tue8AM = DateTime(2026, 3, 10, 8, 0);
  // Tuesday 11 PM (More than 24h)
  final tue11PM = DateTime(2026, 3, 10, 23, 0);
  // Wednesday 10 AM (Exactly 1 day after Tue 10 AM, but 2 days after Mon)
  final wed10AM = DateTime(2026, 3, 11, 10, 0);
  // Same day
  final mon11PM = DateTime(2026, 3, 9, 23, 0);

  test('New user', mon10PM, null, 0, 1);
  test('Consecutive: Mon 10PM -> Tue 8AM (<24h)', tue8AM, mon10PM, 1, 2);
  test('Consecutive: Mon 10PM -> Tue 11PM (>24h)', tue11PM, mon10PM, 1, 2);
  test('Same day login: Mon 10PM -> Mon 11PM', mon11PM, mon10PM, 1, 1);
  test('Gap: Mon 10PM -> Wed 10AM (Reset)', wed10AM, mon10PM, 1, 1);
  test('Long Gap: Mon 10PM -> Sat 10AM (Reset)', DateTime(2026, 3, 14), mon10PM, 1, 1);
}
