import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/error/failure_messages.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/l10n/strings_trip.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/role_badge.dart';
import '../../../core/widgets/state_view.dart';
import '../../reviews/presentation/review_widgets.dart';
import '../../trip/domain/trip.dart' show TripRole;
import '../../trip/domain/trip_form.dart';
import '../domain/match_models.dart';
import 'matching_providers.dart';
import 'matching_widgets.dart';

/// S-15: incoming requests (accept/decline) and the ones I sent.
class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsState();
}

class _RequestsState extends ConsumerState<RequestsScreen> {
  final _busy = <String>{};

  Future<void> _respond(MatchSummary m, bool accept) async {
    if (_busy.contains(m.id)) return;
    // Car: the Driver's yes takes the one seat (and closes other requests), so
    // both roles get a role-specific confirmation first (F-R4.5).
    if (accept && m.isCar) {
      final driver = m.iAmDriver;
      final ok = await showConfirmDialog(
        context,
        title: driver ? R.acceptTitleDriver : R.acceptTitleRider,
        body: driver ? R.acceptBodyDriver : R.acceptBodyRider,
        safeLabel: R.acceptBack,
        confirmLabel: R.acceptConfirm,
        destructive: false,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy.add(m.id));
    final res = await ref.read(inboxProvider.notifier).respond(m, accept: accept);
    if (!mounted) return;
    setState(() => _busy.remove(m.id));
    res.when(
      ok: (s) {
        if (s == MatchStatus.accepted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(T.acceptedTogether)));
          context.push(Routes.match(m.id));
        }
      },
      err: (f) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failureMessage(f)))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(inboxProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(T.requestsTitle),
          bottom: const TabBar(tabs: [Tab(text: T.tabIncoming), Tab(text: T.tabSent)]),
        ),
        body: inbox.when(
          loading: () => const StateView.loading(),
          error: (e, _) => StateView.failure(
            e is AppFailure ? e : const AppFailure(FailureCode.unknown),
            onRetry: () => ref.invalidate(inboxProvider),
          ),
          data: (all) {
            final incoming = all.where((m) => m.isIncomingPending).toList();
            final sent = all.where((m) => m.iAmRequester).toList();
            return TabBarView(children: [
              _list(incoming, const StateView.empty(title: T.noIncoming), incomingList: true),
              _list(sent, const StateView.empty(title: T.noSent), incomingList: false),
            ]);
          },
        ),
      ),
    );
  }

  Widget _list(List<MatchSummary> items, Widget empty, {required bool incomingList}) {
    return RefreshIndicator(
      onRefresh: () => ref.read(inboxProvider.notifier).refresh(),
      child: items.isEmpty
          ? ListView(children: [const SizedBox(height: AppSpacing.xxl), empty])
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.pageH),
              itemCount: items.length,
              itemBuilder: (_, i) => _card(items[i], incomingList),
            ),
    );
  }

  Widget _card(MatchSummary m, bool incomingList) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final busy = _busy.contains(m.id);
    final statusText = switch (m.status) {
      MatchStatus.pending => T.waitingReply,
      MatchStatus.accepted => T.matched,
      MatchStatus.declined => T.requestDeclined,
      // Neutral: no reason, no name of who took the seat (auto-closed or ended).
      MatchStatus.cancelled => m.isCar ? R.requestClosed : T.closedRequest,
    };
    return Card(
      child: InkWell(
        onTap: m.status == MatchStatus.accepted ? () => context.push(Routes.match(m.id)) : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (m.partnerRole != null) ...[
                RoleRow(m.partnerRole!),
                const SizedBox(height: AppSpacing.sm),
              ],
              Row(children: [
                AvatarInitial(name: m.displayName),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(m.displayName, style: theme.textTheme.titleMedium)),
              ]),
              const SizedBox(height: AppSpacing.sm),
              BadgeWrap(m.badges),
              if (m.partnerId != null && m.partnerRole != null) RatingSummary(userId: m.partnerId!, role: m.partnerRole!),
              if (m.mode != null && m.departAt != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text('${m.mode!.label} · ${formatDeparture(m.departAt!, now)}'),
              ],
              if (m.overlapPct != null)
                Text(switch (m.partnerRole) {
                  TripRole.driver => R.overlapRiderView(m.overlapPct!),
                  TripRole.rider => R.overlapDriverView(m.overlapPct!),
                  null => '${T.overlap} ${m.overlapPct}%',
                }),
              const SizedBox(height: AppSpacing.md),
              if (incomingList)
                Row(children: [
                  Expanded(
                    child: AppButton(
                      label: T.accept,
                      variant: AppButtonVariant.success,
                      loading: busy,
                      onPressed: () => _respond(m, true),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppButton(
                      label: T.decline,
                      variant: AppButtonVariant.secondary,
                      onPressed: busy ? null : () => _respond(m, false),
                    ),
                  ),
                ])
              else
                Text(statusText, style: theme.textTheme.labelLarge),
            ],
          ),
        ),
      ),
    );
  }
}
