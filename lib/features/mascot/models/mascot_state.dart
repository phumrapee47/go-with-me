/// The 10 canonical poses of the brand mascot (see assets/mascot/states/).
/// Never add a new pose without a matching PNG (and later Rive state) — the
/// character identity itself must never be regenerated ad hoc.
enum MascotState {
  idle,
  hello,
  searching,
  found,
  happy,
  waiting,
  rain,
  walking,
  safe,
  goodbye;

  String get asset => 'assets/mascot/states/mascot_$name.png';
}
