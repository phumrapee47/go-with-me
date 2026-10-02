/// Metres under 1000 ("800 ม."), else km with one decimal ("1.5 กม.", "5.0 กม.").
String formatMetres(int metres) => metres < 1000 ? '$metres ม.' : '${(metres / 1000).toStringAsFixed(1)} กม.';

/// Driver drop-off limit bounds (0009 CHECK: 500..5000, multiple of 100, default 2000).
const int dropoffMinM = 500;
const int dropoffMaxM = 5000;
const int dropoffStepM = 100;
const int dropoffDefaultM = 2000;
const List<int> dropoffChipsM = [1000, 2000, 3000, 5000];

/// Snaps to the 0009 rule: 500..5000 in steps of 100.
int clampDropoff(int m) => ((m.clamp(dropoffMinM, dropoffMaxM)) / dropoffStepM).round() * dropoffStepM;
