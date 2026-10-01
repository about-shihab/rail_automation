import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/credit_transaction.dart';
import '../services/admin_service.dart';
import '../services/firebase_user_service.dart';
import '../utils/app_theme.dart';

// ── Shared helpers ───────────────────────────────────────────────────────────

void _toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppColors.error : const Color(0xFF059669),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Text(msg),
      ),
    );
}

String _errText(Object e) =>
    e is AdminException ? e.message : 'Something went wrong. Please try again.';

String _fmtDate(DateTime d) {
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final l = d.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final mm = l.minute.toString().padLeft(2, '0');
  final ap = l.hour >= 12 ? 'PM' : 'AM';
  return '${l.day} ${m[l.month - 1]} ${l.year}, $h:$mm $ap';
}

/// Small pill used on the Profile tab card to show pending recharge count.
class AdminPendingBadge extends StatelessWidget {
  const AdminPendingBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: AdminService().watchPendingCount(),
      builder: (context, snap) {
        final n = snap.data ?? 0;
        if (n == 0) return const Icon(Icons.chevron_right_rounded);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$n',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        );
      },
    );
  }
}

// ── Screen ───────────────────────────────────────────────────────────────────

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAdmin = context.watch<FirebaseUserService>().isAdmin;

    if (!isAdmin) {
      return Scaffold(
        backgroundColor: AppColors.scaffoldBg(isDark),
        appBar: AppBar(title: const Text('Admin')),
        body: Center(
          child: Text(
            'Admin access required',
            style: TextStyle(color: AppColors.textMuted(isDark)),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg(isDark),
        appBar: AppBar(
          title: const Text('Admin Panel'),
          elevation: 0,
          bottom: const TabBar(
            indicatorColor: AppColors.primary,
            tabs: [
              Tab(icon: Icon(Icons.people_alt_rounded), text: 'Users'),
              Tab(icon: Icon(Icons.receipt_long_rounded), text: 'Recharges'),
            ],
          ),
        ),
        body: const TabBarView(children: [_UsersTab(), _RechargesTab()]),
      ),
    );
  }
}

// ── Users tab ────────────────────────────────────────────────────────────────

class _UsersTab extends StatefulWidget {
  const _UsersTab();
  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab>
    with AutomaticKeepAliveClientMixin {
  late final Stream<List<AdminUser>> _stream = AdminService().watchUsers();
  final _search = TextEditingController();
  String _q = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search phone, name or email',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _search.clear();
                        setState(() => _q = '');
                      },
                    ),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<AdminUser>>(
            stream: _stream,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not load users.\n${snap.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted(isDark)),
                    ),
                  ),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final users = snap.data!.where((u) {
                if (_q.isEmpty) return true;
                return u.phone.toLowerCase().contains(_q) ||
                    u.displayName.toLowerCase().contains(_q) ||
                    u.email.toLowerCase().contains(_q);
              }).toList();

              if (users.isEmpty) {
                return Center(
                  child: Text(
                    'No users found',
                    style: TextStyle(color: AppColors.textMuted(isDark)),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: users.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _UserCard(
                  user: users[i],
                  isDark: isDark,
                  onTap: () => _AdjustCreditSheet.show(context, users[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  final AdminUser user;
  final bool isDark;
  final VoidCallback onTap;
  const _UserCard({
    required this.user,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = user.displayName.isNotEmpty ? user.displayName : user.phone;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: Icon(
                  user.isAdmin
                      ? Icons.admin_panel_settings_rounded
                      : Icons.person_rounded,
                  color: AppColors.primary,
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: user.isActive
                        ? AppColors.success
                        : AppColors.textMuted(isDark),
                    border: Border.all(
                      color: AppColors.cardBg(isDark),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: AppColors.textPrimary(isDark),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user.displayName.isNotEmpty ? user.phone : user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted(isDark),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bolt_rounded,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 3),
                Text(
                  '${user.credits}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdjustCreditSheet extends StatefulWidget {
  final AdminUser user;
  const _AdjustCreditSheet({required this.user});

  static Future<void> show(BuildContext context, AdminUser user) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.cardBg(
        Theme.of(context).brightness == Brightness.dark,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AdjustCreditSheet(user: user),
    );
  }

  @override
  State<_AdjustCreditSheet> createState() => _AdjustCreditSheetState();
}

class _AdjustCreditSheetState extends State<_AdjustCreditSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _apply(int sign) async {
    final v = int.tryParse(_amount.text.trim());
    if (v == null || v <= 0 || v > 1000) {
      _toast(context, 'Enter an amount between 1 and 1000', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final newBalance = await AdminService().adjustCredit(
        phone: widget.user.phone,
        delta: v * sign,
        note: _note.text,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF059669),
          content: Text(
            '${sign > 0 ? 'Added' : 'Removed'} $v credit(s). '
            'New balance: $newBalance',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toast(context, _errText(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final u = widget.user;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              u.displayName.isNotEmpty ? u.displayName : u.phone,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary(isDark),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${u.phone} · Current balance: ${u.credits}',
              style: TextStyle(color: AppColors.textMuted(isDark)),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _amount,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Credits',
                prefixIcon: Icon(Icons.bolt_rounded),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [1, 5, 10, 25, 50]
                  .map(
                    (n) => ActionChip(
                      label: Text('$n'),
                      onPressed: _busy
                          ? null
                          : () => setState(() => _amount.text = '$n'),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              enabled: !_busy,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _busy ? null : () => _apply(-1),
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                    label: const Text('Decrease'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _busy ? null : () => _apply(1),
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_circle_outline_rounded),
                    label: const Text('Increase'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Recharges tab ────────────────────────────────────────────────────────────

class _RechargesTab extends StatefulWidget {
  const _RechargesTab();
  @override
  State<_RechargesTab> createState() => _RechargesTabState();
}

class _RechargesTabState extends State<_RechargesTab>
    with AutomaticKeepAliveClientMixin {
  late final Stream<List<CreditTransaction>> _stream =
      AdminService().watchRequests();
  RequestState _filter = RequestState.pending;
  final Set<String> _busy = {};

  @override
  bool get wantKeepAlive => true;

  Future<bool> _confirm(String title, String body, String action,
      {bool danger = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(backgroundColor: AppColors.error)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _approve(CreditTransaction t) async {
    final ok = await _confirm(
      'Approve recharge?',
      'Add ${t.credits} credits to ${t.phone}?\n\n'
          'TrxID: ${t.trxId}\nAmount: ৳${t.amount.toStringAsFixed(0)}\n\n'
          'Verify this TrxID in your bKash app first.',
      'Approve',
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add(t.id));
    try {
      await AdminService().approveRequest(t.id);
      if (mounted) _toast(context, '${t.credits} credits added to ${t.phone}');
    } catch (e) {
      if (mounted) _toast(context, _errText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(t.id));
    }
  }

  Future<void> _reject(CreditTransaction t) async {
    final ok = await _confirm(
      'Reject recharge?',
      'Reject TrxID ${t.trxId} from ${t.phone}? No credits will be added.',
      'Reject',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add(t.id));
    try {
      await AdminService().rejectRequest(t.id);
      if (mounted) _toast(context, 'Request rejected');
    } catch (e) {
      if (mounted) _toast(context, _errText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(t.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<List<CreditTransaction>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load requests.\n${snap.error}',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted(isDark)),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final all = snap.data!;
        int count(RequestState s) =>
            all.where((t) => AdminService.stateOf(t.status) == s).length;
        final shown =
            all.where((t) => AdminService.stateOf(t.status) == _filter).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  for (final s in RequestState.values) ...[
                    ChoiceChip(
                      label: Text(
                        '${s.name[0].toUpperCase()}${s.name.substring(1)} '
                        '(${count(s)})',
                      ),
                      selected: _filter == s,
                      onSelected: (_) => setState(() => _filter = s),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? Center(
                      child: Text(
                        'No ${_filter.name} requests',
                        style: TextStyle(color: AppColors.textMuted(isDark)),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: shown.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final t = shown[i];
                        return _RequestCard(
                          t: t,
                          isDark: isDark,
                          busy: _busy.contains(t.id),
                          onApprove: () => _approve(t),
                          onReject: () => _reject(t),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _RequestCard extends StatelessWidget {
  final CreditTransaction t;
  final bool isDark;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _RequestCard({
    required this.t,
    required this.isDark,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final state = AdminService.stateOf(t.status);
    final color = switch (state) {
      RequestState.pending => AppColors.warning,
      RequestState.approved => AppColors.success,
      RequestState.rejected => AppColors.error,
    };

    Widget line(IconData icon, String text, {VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(icon, size: 15, color: AppColors.textMuted(isDark)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary(isDark),
                    ),
                  ),
                ),
                if (onTap != null)
                  Icon(Icons.copy_rounded,
                      size: 14, color: AppColors.textMuted(isDark)),
              ],
            ),
          ),
        );

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '৳${t.amount.toStringAsFixed(0)}  →  ${t.credits} credits',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary(isDark),
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  state.name.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 10.5,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          line(Icons.person_outline_rounded, 'User: ${t.phone}'),
          line(Icons.phone_android_rounded, 'bKash sender: ${t.bkashSender}'),
          line(
            Icons.tag_rounded,
            'TrxID: ${t.trxId}',
            onTap: () {
              Clipboard.setData(ClipboardData(text: t.trxId));
              _toast(context, 'TrxID copied');
            },
          ),
          line(Icons.schedule_rounded, _fmtDate(t.createdAt)),
          if (state == RequestState.pending) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                    ),
                    onPressed: busy ? null : onReject,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : onApprove,
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
