import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/l10n/strings_dual.dart';
import '../../../core/l10n/strings_p4.dart';
import '../../../core/l10n/strings_trip.dart';
import '../../../core/map/app_map.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/state_view.dart';
import '../../geo/domain/location_service.dart';
import '../../geo/presentation/current_location.dart';
import '../../geo/presentation/geo_providers.dart';
import '../../mascot/widgets/mascot_greeting.dart';
import '../../mascot/widgets/rain_notification.dart';
import '../../matching/domain/match_models.dart';
import '../../matching/presentation/matching_providers.dart';
import '../../matching/presentation/matching_widgets.dart';
import '../../presets/presentation/quick_home_card.dart';
import '../../profile/presentation/profile_providers.dart';
import '../../roles/domain/role_state.dart';
import '../../roles/presentation/role_providers.dart';
import '../../roles/presentation/role_strip.dart' show performRoleSwitch;
import '../../safety/presentation/safety_providers.dart';
import '../../trip/domain/trip.dart';
import '../../trip/domain/trip_form.dart';
import '../../trip/presentation/trip_providers.dart';
import '../../trip/presentation/trip_tone.dart';
import 'home_providers.dart';

/// Round 9 (US-2/T4, RC-5/RC-6/RC-7): the map is now the full-screen background (no
/// framing card), a street-level GPS zoom (15-15.5) with a smooth animated camera move
/// and a pulsing "you are here" dot, a transparent floating header instead of the old
/// solid `AppBar`, and a floating rounded search panel at the bottom instead of the old
/// framed `Expanded(flex:5, ...)` list. All existing actions/providers (search, create
/// trip, role switch, home/work shortcuts, `obtainCurrentLocation`'s BUG-2-safe
/// permission/timeout flow) are reused unchanged — only the chrome changed.
class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

/// Street-level zoom band the AC asks for (15.0-15.5); fallback (no/denied permission,
/// or a read failure) stays at a city-wide zoom so a Bangkok-centre fallback point never
/// looks like it claims to be the user's real street.
const _kGpsZoom = 15.2;
const _kFallbackZoom = 12.0;

class _HomeTabState extends ConsumerState<HomeTab> with SingleTickerProviderStateMixin {
  final _mapController = MapController();
  LatLng? _me;
  bool _locating = false;
  AnimationController? _anim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locateSilently());
  }

  @override
  void dispose() {
    _anim?.dispose();
    super.dispose();
  }

  /// On first open: only move the camera if permission was already granted earlier —
  /// never shows the consent dialog / OS prompt itself on a plain tab open (that stays
  /// an explicit action, same as every other screen in the app). Any error/denial here
  /// is silent (the map just stays at the fallback) so opening Home never pops a dialog
  /// or a snackbar unprompted.
  Future<void> _locateSilently() async {
    if (!mounted) return;
    final loc = ref.read(locationServiceProvider);
    final state = await loc.permission();
    if (state != LocationPermissionState.granted || !mounted) return;
    final pos = await loc.currentPosition();
    if (!mounted) return;
    pos.when(ok: _animateTo, err: (_) {});
  }

  /// 🧭 recenter (explicit tap): the full BUG-2-safe consent/permission/timeout flow —
  /// unchanged, just reused (US-2 AC: must not regress round-8's fix).
  Future<void> _locate() async {
    if (!mounted || _locating) return;
    setState(() => _locating = true);
    final p = await obtainCurrentLocation(context, ref);
    if (!mounted) return;
    setState(() => _locating = false);
    if (p == null) return;
    _animateTo(p);
  }

  void _animateTo(LatLng target) {
    // BUG-QA9-2: reduced-motion must jump straight to the target, same pattern as `_PulseDot`
    // in this file and `DeckSwipeCardState`/`AnimatedSwitcher` in commute_card_deck.dart.
    if (MediaQuery.disableAnimationsOf(context)) {
      _anim?.dispose();
      _anim = null;
      _mapController.move(target, _kGpsZoom);
      setState(() => _me = target);
      return;
    }
    final fromCenter = _me ?? _mapController.camera.center;
    final fromZoom = _mapController.camera.zoom;
    _anim?.dispose();
    final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
    final curve = CurvedAnimation(parent: c, curve: Curves.easeInOutCubic);
    curve.addListener(() {
      final t = curve.value;
      final lat = fromCenter.latitude + (target.latitude - fromCenter.latitude) * t;
      final lng = fromCenter.longitude + (target.longitude - fromCenter.longitude) * t;
      final zoom = fromZoom + (_kGpsZoom - fromZoom) * t;
      _mapController.move(LatLng(lat, lng), zoom);
    });
    _anim = c;
    setState(() => _me = target);
    c.forward();
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(currentProfileProvider).valueOrNull?.displayName ?? '';
    final trip = ref.watch(activeTripProvider);
    final nearby = ref.watch(nearbyProvider);
    final t = trip.valueOrNull;
    final candidates = nearby.valueOrNull ?? const <MatchCandidate>[];
    final noContacts = ref.watch(contactsProvider).valueOrNull?.isEmpty ?? false;
    final isRaining = ref.watch(isRainingProvider).valueOrNull ?? false;
    final tone = context.tone;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // RC-5 FullBleedHomeMap: no framing card anymore, the map IS the background.
          Positioned.fill(
            child: AppMap(
              controller: _mapController,
              center: _me ?? t?.origin ?? defaultMapCenter,
              zoom: _me != null ? _kGpsZoom : (t == null ? _kFallbackZoom : 13),
              route: t?.route ?? const [],
              routeTone: toneOfTripRole(t?.role),
              areas: [for (final c in candidates) MapArea(center: c.approxOrigin, radiusM: blurAreaRadiusM)],
              pins: t == null
                  ? const []
                  : [
                      MapPin(point: t.origin, icon: Icons.trip_origin),
                      MapPin(point: t.dest, icon: Icons.place, color: AppColors.danger),
                    ],
              markers: _me == null ? const [] : [Marker(point: _me!, width: 28, height: 28, child: const _PulseDot())],
              showZoomButtons: false,
              onMyLocation: _locate,
            ),
          ),
          if (isRaining) const Positioned(top: 0, left: 0, right: 0, child: RainNotification()),
          // RC-6 FloatingHomeHeader: transparent, text-shadow instead of a solid AppBar.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, AppSpacing.sm, AppSpacing.pageH, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name.isEmpty ? S.tabHome : 'สวัสดี, $name',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              shadows: const [Shadow(color: Colors.black45, blurRadius: 6)],
                            ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(right: AppSpacing.sm),
                      child: _RoleSwitchCapsule(),
                    ),
                    _FloatingIconButton(
                      tooltip: P.safetyShield,
                      icon: Icons.shield_outlined,
                      onTap: () => context.push(Routes.safety),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 🧭 recenter (AC: bottom-right, above the floating search panel).
          Positioned(
            right: AppSpacing.lg,
            bottom: 280,
            child: _FloatingIconButton(
              tooltip: 'ไปที่ตำแหน่งของฉัน',
              icon: Icons.my_location,
              loading: _locating,
              onTap: _locate,
            ),
          ),
          // RC-7 FloatingSearchCard area: rounded-top white panel over the map.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _FloatingSearchPanel(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(AppSpacing.pageH),
                children: [
                  if (noContacts) ...[
                    AppCard(
                      tone: AppCardTone.warning,
                      onTap: () => context.push(Routes.safetyContacts),
                      child: Row(children: [
                        Icon(Icons.contact_phone_outlined, color: tone.warningInk),
                        const SizedBox(width: AppSpacing.md),
                        const Expanded(child: Text(P.noContactsCard)),
                      ]),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  ...trip.when(
                    loading: () => [const SizedBox(height: 120, child: StateView.loading())],
                    error: (e, _) => [
                      SizedBox(
                        height: 200,
                        child: StateView.failure(
                          e is AppFailure ? e : const AppFailure(FailureCode.unknown),
                          onRetry: () => ref.invalidate(activeTripProvider),
                        ),
                      ),
                    ],
                    data: (t) => t == null ? _noTrip(context) : _withTrip(context, ref, t, nearby),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _noTrip(BuildContext context) => [
        Row(children: [
          const MascotGreeting(size: 40),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(S.homeGreeting, style: Theme.of(context).textTheme.titleMedium)),
        ]),
        const SizedBox(height: AppSpacing.md),
        // Round 6 (US-39): one-tap home trip (car only). Peer modes keep the wizard below.
        const QuickHomeCard(),
        const SizedBox(height: AppSpacing.md),
        const HintCard(T.homeNoTripBody),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: T.homeCreatePrompt,
          icon: Icons.add_road,
          onPressed: () => context.push(Routes.tripNew),
        ),
      ];

  List<Widget> _withTrip(BuildContext context, WidgetRef ref, Trip t, AsyncValue<List<MatchCandidate>> nearby) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    return [
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(T.homeMyTrip, style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(t.destLabel.isEmpty ? 'ปลายทาง' : t.destLabel,
                style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: AppSpacing.xs),
            Text('${t.mode.label} · ${formatDeparture(t.departAt, now)}'),
            if (t.distanceM > 0) Text(formatRouteSummary(t.distanceM, t.durationS)),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      Row(children: [
        Expanded(child: Text(T.homeNearbyHeader, style: theme.textTheme.titleMedium)),
        TextButton(onPressed: () => context.go(Routes.nearby), child: const Text(T.homeSeeAll)),
      ]),
      ...nearby.when(
        loading: () => [const SizedBox(height: 80, child: StateView.loading())],
        error: (e, _) => [
          SizedBox(
            height: 180,
            child: StateView.failure(
              e is AppFailure ? e : const AppFailure(FailureCode.unknown),
              onRetry: () => ref.read(nearbyProvider.notifier).refresh(force: true),
            ),
          ),
        ],
        data: (items) => items.isEmpty
            ? const [
                StateView.empty(
                  icon: Icons.people_outline,
                  title: T.homeNobodyNear,
                  message: T.homeNobodyNearBody,
                ),
              ]
            : [
                for (final c in items.take(3))
                  Card(
                    child: ListTile(
                      minTileHeight: AppSpacing.minTap,
                      leading: AvatarInitial(name: c.displayName),
                      title: Text(c.displayName),
                      subtitle: Text('${c.mode.label} · ${T.overlap} ${c.overlapPct}%'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(Routes.candidate(c.tripId)),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(T.mapPrivacy, style: TextStyle(color: context.tone.textSecondary)),
                ),
              ],
      ),
    ];
  }
}

/// RC-5: a blue dot + soft pulsing halo at the user's live GPS position.
///
/// Implemented as a *finite* (non-repeating-forever) pulse: a plain infinite
/// `AnimationController.repeat()` never settles, which makes every existing
/// `tester.pumpAndSettle()` call across the test suite hang/time out the moment this
/// marker is on screen (nothing else in the codebase uses an unbounded repeat for
/// exactly this reason). `reverse: true` + a bounded number of cycles keeps the
/// "เต้น" motion AC while staying a normal, completable animation.
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  static const _cycles = 6;
  // Round 9 P1 follow-up: `MediaQuery.disableAnimationsOf` is an InheritedWidget lookup and
  // must not be called until `initState()` has returned — `didChangeDependencies()` is the
  // correct first-access point. Guarded so the animation is only (re-)started once, not on
  // every later dependency change (e.g. a MediaQuery rebuild from a rotation/text-scale change).
  bool _animationStarted = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_animationStarted) {
      _animationStarted = true;
      if (!MediaQuery.disableAnimationsOf(context)) {
        _c.repeat(reverse: true, count: _cycles);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'ตำแหน่งของคุณ',
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (0.5 * t).clamp(0.0, 1.0),
                child: Container(
                  width: 12 + 16 * t,
                  height: 12 + 16 * t,
                  decoration: const BoxDecoration(color: Color(0x551E6FD9), shape: BoxShape.circle),
                ),
              ),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(color: AppColors.blue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// RC-6 RoleSwitchCapsule: the floating header's own [🚗 คนขับ | 🎒 คนนั่ง] switch (round 9,
/// QA9-P0 bug #2) — visually a capsule pinned in the header itself, not the app-wide
/// `RoleStrip` bar under the AppBar. Reuses `performRoleSwitch`/`roleControllerProvider`
/// unchanged: only the presentation is new.
class _RoleSwitchCapsule extends ConsumerWidget {
  const _RoleSwitchCapsule();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(roleControllerProvider);
    final active = s.active;
    if (active == null) return const SizedBox.shrink();
    final switching = s.switching.isSwitching;
    final canDriver = s.registered == true || active == ActiveRole.driver;

    return Semantics(
      container: true,
      label: D.a11yModeCurrent(active == ActiveRole.driver ? D.roleWordDriver : D.roleWordRider),
      child: Material(
        color: Colors.black.withValues(alpha: 0.35),
        shape: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _capsuleSegment(
                context,
                ref,
                role: ActiveRole.driver,
                active: active,
                switching: switching,
                enabled: canDriver,
                icon: Icons.drive_eta,
                label: D.roleWordDriver,
              ),
              _capsuleSegment(
                context,
                ref,
                role: ActiveRole.rider,
                active: active,
                switching: switching,
                enabled: true,
                icon: Icons.event_seat,
                label: D.roleWordRider,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _capsuleSegment(
    BuildContext context,
    WidgetRef ref, {
    required ActiveRole role,
    required ActiveRole active,
    required bool switching,
    required bool enabled,
    required IconData icon,
    required String label,
  }) {
    final selected = role == active;
    final busy = switching && _switchTarget(ref) == role;
    return Semantics(
      button: true,
      selected: selected,
      label: D.a11yModeCurrent(label),
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: AppSpacing.minTap, minHeight: AppSpacing.minTap),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: Key(role == ActiveRole.driver ? 'home-role-capsule-driver' : 'home-role-capsule-rider'),
            customBorder: const StadiumBorder(),
            onTap: (!enabled || switching || selected) ? null : () => performRoleSwitch(context, ref, role),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: 0.9) : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  busy
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: selected ? Colors.black87 : Colors.white),
                        )
                      : Icon(icon, size: 16, color: selected ? Colors.black87 : Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? Colors.black87 : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  ActiveRole? _switchTarget(WidgetRef ref) => ref.watch(roleControllerProvider.select((s) => s.switching.target));
}

class _FloatingIconButton extends StatelessWidget {
  const _FloatingIconButton({required this.icon, required this.onTap, this.tooltip, this.loading = false});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool loading;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Material(
          color: context.tone.surface,
          elevation: 3,
          shape: const CircleBorder(),
          child: IconButton(
            tooltip: tooltip,
            constraints: const BoxConstraints(minWidth: AppSpacing.minTap, minHeight: AppSpacing.minTap),
            icon: loading
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: context.tone.text))
                : Icon(icon, color: context.tone.text),
            onPressed: onTap,
          ),
        ),
      );
}

/// RC-7: rounded-top white panel over the map, soft ambient shadow, no hard border
/// (US-7/US-2 AC "ไม่มีกล่องซ้อนกล่อง" — this is now the single outer container, where
/// before the panel sat inside a boxed `Expanded` column next to a boxed map).
class _FloatingSearchPanel extends StatelessWidget {
  const _FloatingSearchPanel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.55),
        decoration: BoxDecoration(
          color: tone.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
          boxShadow: tone.cardShadow,
        ),
        child: child,
      ),
    );
  }
}
