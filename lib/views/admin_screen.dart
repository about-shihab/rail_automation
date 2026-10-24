import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/credit_transaction.dart';
import '../services/admin_service.dart';
import '../services/firebase_user_service.dart';
import '../services/notification_service.dart';
import '../utils/app_theme.dart';
import 'admin_config_tab.dart';

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

String _fmtDate(DateTime? d) {
  if (d == null) return 'Never';
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

// ── Main Screen ──────────────────────────────────────────────────────────────

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
      length: 5,
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg(isDark),
        appBar: AppBar(
          title: const Text('Admin'),
          elevation: 0,
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: AppColors.primary,
            tabs: [
              Tab(icon: Icon(Icons.people_alt_rounded), text: 'Users'),
              Tab(icon: Icon(Icons.history_rounded), text: 'User Logs'),
              Tab(icon: Icon(Icons.receipt_long_rounded), text: 'Transactions'),
              Tab(icon: Icon(Icons.notifications_active_rounded), text: 'Notifications'),
              Tab(icon: Icon(Icons.settings_rounded), text: 'Configuration'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _UsersTab(),
            _UserLogsTab(),
            _RechargesTab(),
            _NotificationsTab(),
            AdminConfigTab(),
          ],
        ),
      ),
    );
  }
}

// ── Users Tab ────────────────────────────────────────────────────────────────

enum _UserFilter { all, newUsers, active, blocked }

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
  _UserFilter _filter = _UserFilter.all;

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

    return StreamBuilder<List<AdminUser>>(
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

        final all = snap.data!;
        final newCount = all.where((u) => u.isNewUser).length;
        final activeCount = all.where((u) => u.isActive && !u.isBlocked).length;
        final blockedCount = all.where((u) => u.isBlocked).length;

        final users = all.where((u) {
          if (_filter == _UserFilter.newUsers && !u.isNewUser) return false;
          if (_filter == _UserFilter.active && (!u.isActive || u.isBlocked)) {
            return false;
          }
          if (_filter == _UserFilter.blocked && !u.isBlocked) return false;
          if (_q.isEmpty) return true;
          return u.phone.toLowerCase().contains(_q) ||
              u.displayName.toLowerCase().contains(_q) ||
              u.email.toLowerCase().contains(_q);
        }).toList();

        if (_filter == _UserFilter.newUsers) {
          users.sort((a, b) {
            final at = a.createdAt ?? a.lastActiveAt;
            final bt = b.createdAt ?? b.lastActiveAt;
            if (at == null && bt == null) return 0;
            if (at == null) return 1;
            if (bt == null) return -1;
            return bt.compareTo(at);
          });
        }

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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text('All (${all.length})'),
                      selected: _filter == _UserFilter.all,
                      onSelected: (_) => setState(() => _filter = _UserFilter.all),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      avatar: const Icon(
                        Icons.fiber_new_rounded,
                        size: 18,
                        color: Color(0xFF10B981),
                      ),
                      label: Text(
                        'New Users ($newCount)',
                        style: TextStyle(
                          color: _filter == _UserFilter.newUsers
                              ? const Color(0xFF10B981)
                              : null,
                          fontWeight: _filter == _UserFilter.newUsers
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      selected: _filter == _UserFilter.newUsers,
                      selectedColor: const Color(0xFF10B981).withValues(alpha: 0.18),
                      onSelected: (_) => setState(() => _filter = _UserFilter.newUsers),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('Active ($activeCount)'),
                      selected: _filter == _UserFilter.active,
                      onSelected: (_) => setState(() => _filter = _UserFilter.active),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('Blocked ($blockedCount)'),
                      selected: _filter == _UserFilter.blocked,
                      onSelected: (_) => setState(() => _filter = _UserFilter.blocked),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: users.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _filter == _UserFilter.newUsers
                                  ? Icons.person_add_disabled_rounded
                                  : Icons.people_outline_rounded,
                              size: 44,
                              color: AppColors.textMuted(isDark),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _filter == _UserFilter.newUsers
                                  ? 'No new users registered recently'
                                  : 'No users found',
                              style: TextStyle(color: AppColors.textMuted(isDark)),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: users.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _UserCard(
                        user: users[i],
                        isDark: isDark,
                        onTap: () => _UserActionSheet.show(context, users[i]),
                      ),
                    ),
            ),
          ],
        );
      },
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
                backgroundColor: user.isBlocked
                    ? AppColors.error.withValues(alpha: 0.15)
                    : (user.isNewUser
                        ? const Color(0xFF10B981).withValues(alpha: 0.15)
                        : AppColors.primary.withValues(alpha: 0.15)),
                child: Icon(
                  user.isBlocked
                      ? Icons.block_rounded
                      : (user.isAdmin
                          ? Icons.admin_panel_settings_rounded
                          : (user.isNewUser
                              ? Icons.person_add_rounded
                              : Icons.person_rounded)),
                  color: user.isBlocked
                      ? AppColors.error
                      : (user.isNewUser
                          ? const Color(0xFF10B981)
                          : AppColors.primary),
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
                    color: user.isBlocked
                        ? AppColors.error
                        : (user.isActive
                            ? AppColors.success
                            : AppColors.textMuted(isDark)),
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: AppColors.textPrimary(isDark),
                        ),
                      ),
                    ),
                    if (user.isNewUser) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFF10B981).withValues(alpha: 0.35),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fiber_new_rounded, size: 12, color: Color(0xFF10B981)),
                            SizedBox(width: 2),
                            Text(
                              'NEW',
                              style: TextStyle(
                                color: Color(0xFF10B981),
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (user.isBlocked) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'BLOCKED',
                          style: TextStyle(
                            color: AppColors.error,
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ] else if (user.isAdmin) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'ADMIN',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  user.displayName.isNotEmpty ? user.phone : (user.email.isNotEmpty ? user.email : user.phone),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted(isDark),
                  ),
                ),
                if (user.createdAt != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 10.5, color: AppColors.textMuted(isDark)),
                      const SizedBox(width: 4),
                      Text(
                        'Joined: ${_fmtDate(user.createdAt)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted(isDark),
                        ),
                      ),
                    ],
                  ),
                ],
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
                const Icon(Icons.bolt_rounded, size: 16, color: AppColors.primary),
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

// ── User Action Sheet (Manage User) ──────────────────────────────────────────

class _UserActionSheet extends StatelessWidget {
  final AdminUser user;
  const _UserActionSheet({required this.user});

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
      builder: (_) => _UserActionSheet(user: user),
    );
  }

  Future<void> _toggleBlock(BuildContext context) async {
    final willBlock = !user.isBlocked;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(willBlock ? 'Block User?' : 'Unblock User?'),
        content: Text(
          willBlock
              ? 'Are you sure you want to block ${user.phone}? They will not be able to use the app.'
              : 'Are you sure you want to unblock ${user.phone}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: willBlock
                ? FilledButton.styleFrom(backgroundColor: AppColors.error)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(willBlock ? 'Block' : 'Unblock'),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    try {
      await AdminService().toggleBlockUser(
        phone: user.phone,
        block: willBlock,
      );
      if (context.mounted) {
        Navigator.pop(context); // Close bottom sheet
        _toast(context, willBlock ? 'User blocked successfully' : 'User unblocked successfully');
      }
    } catch (e) {
      if (context.mounted) {
        _toast(context, _errText(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: user.isBlocked
                    ? AppColors.error.withValues(alpha: 0.15)
                    : AppColors.primary.withValues(alpha: 0.15),
                child: Icon(
                  user.isBlocked ? Icons.block_rounded : Icons.person_rounded,
                  color: user.isBlocked ? AppColors.error : AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName.isNotEmpty ? user.displayName : user.phone,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary(isDark),
                      ),
                    ),
                    Text(
                      '${user.phone} · Balance: ${user.credits} credits',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted(isDark),
                      ),
                    ),
                    if (user.createdAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Joined: ${_fmtDate(user.createdAt)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textMuted(isDark),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bolt_rounded, color: AppColors.primary, size: 26),
            title: const Text('Increase or Decrease Credit', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('Add or deduct credits directly (Current: ${user.credits})'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.pop(context);
              _AdjustCreditSheet.show(context, user);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history_rounded, color: Color(0xFF10B981), size: 26),
            title: const Text('User Activity Logs', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('View search, booking, login & credit records for ${user.phone}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.pop(context);
              _UserLogsSheet.show(context, user);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              user.isBlocked ? Icons.check_circle_outline_rounded : Icons.block_rounded,
              color: user.isBlocked ? AppColors.success : AppColors.error,
              size: 26,
            ),
            title: Text(
              user.isBlocked ? 'Unblock User' : 'Block User',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: user.isBlocked ? AppColors.success : AppColors.error,
              ),
            ),
            subtitle: Text(
              user.isBlocked
                  ? 'Restore account access'
                  : 'Suspend this user account from automation',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _toggleBlock(context),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.send_rounded, color: Color(0xFF0284C7), size: 24),
            title: const Text('Send Direct Notification', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('Send a custom notification to ${user.phone}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.pop(context);
              _SendNotificationSheet.show(context, initialTargetPhone: user.phone);
            },
          ),
        ],
      ),
    );
  }
}

// ── Credit Adjustment Sheet ──────────────────────────────────────────────────

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

// ── Recharges Tab (Transactions Approval) ───────────────────────────────────

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
      'Approve transaction?',
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
      'Reject transaction?',
      'Reject TrxID ${t.trxId} from ${t.phone}? No credits will be added.',
      'Reject',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add(t.id));
    try {
      await AdminService().rejectRequest(t.id);
      if (mounted) _toast(context, 'Transaction rejected');
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
                'Could not load transactions.\n${snap.error}',
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
                        'No ${_filter.name} transactions',
                        style: TextStyle(color: AppColors.textMuted(isDark)),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
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

// ── Notifications Tab ────────────────────────────────────────────────────────

class _NotificationsTab extends StatelessWidget {
  const _NotificationsTab();

  Future<void> _confirmClearAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All Notifications?'),
        content: const Text(
          'This will permanently delete all previously sent notifications from the database. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (ok != true || !context.mounted) return;
    try {
      await AdminService().clearAllNotifications();
      await NotificationService().clearSeenIds();
      if (context.mounted) _toast(context, 'All notifications cleared successfully');
    } catch (e) {
      if (context.mounted) _toast(context, _errText(e), error: true);
    }
  }

  Future<void> _confirmDeleteSingle(BuildContext context, AppNotification n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Notification?'),
        content: Text('Delete "${n.title}" from notification history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true || !context.mounted) return;
    try {
      await AdminService().deleteNotification(n.id);
      if (context.mounted) _toast(context, 'Notification deleted');
    } catch (e) {
      if (context.mounted) _toast(context, _errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () => _SendNotificationSheet.show(context),
        icon: const Icon(Icons.add_alert_rounded),
        label: const Text('Send Notification', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: AdminService().watchNotifications(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load notifications.\n${snap.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted(isDark)),
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final list = snap.data!;
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none_rounded, size: 54, color: AppColors.textMuted(isDark)),
                  const SizedBox(height: 12),
                  Text(
                    'No notifications sent yet',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary(isDark),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap "Send Notification" below to broadcast or notify a user.',
                    style: TextStyle(color: AppColors.textMuted(isDark), fontSize: 13),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                child: Row(
                  children: [
                    Text(
                      'Sent History (${list.length})',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: AppColors.textPrimary(isDark),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.delete_sweep_rounded, size: 17),
                      label: const Text('Clear All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () => _confirmClearAll(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 80),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final n = list[i];
                    final isBroadcast = n.target == 'all';
                    return AppCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isBroadcast
                                      ? const Color(0xFF0284C7).withValues(alpha: 0.15)
                                      : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isBroadcast ? Icons.campaign_rounded : Icons.person_pin_rounded,
                                      size: 14,
                                      color: isBroadcast ? const Color(0xFF0284C7) : const Color(0xFFF59E0B),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isBroadcast ? 'ALL USERS' : 'USER: ${n.targetPhone ?? n.target}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isBroadcast ? const Color(0xFF0284C7) : const Color(0xFFF59E0B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              if (n.createdAt != null) ...[
                                Text(
                                  _fmtDate(n.createdAt!),
                                  style: TextStyle(fontSize: 11, color: AppColors.textMuted(isDark)),
                                ),
                                const SizedBox(width: 6),
                              ],
                              InkWell(
                                onTap: () => _confirmDeleteSingle(context, n),
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 17,
                                    color: AppColors.textMuted(isDark),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            n.title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary(isDark),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            n.body,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary(isDark),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Send Notification Sheet ──────────────────────────────────────────────────

class _SendNotificationSheet extends StatefulWidget {
  final String? initialTargetPhone;
  const _SendNotificationSheet({this.initialTargetPhone});

  static Future<void> show(BuildContext context, {String? initialTargetPhone}) {
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
      builder: (_) => _SendNotificationSheet(initialTargetPhone: initialTargetPhone),
    );
  }

  @override
  State<_SendNotificationSheet> createState() => _SendNotificationSheetState();
}

class _SendNotificationSheetState extends State<_SendNotificationSheet> {
  late bool _isBroadcast = widget.initialTargetPhone == null;
  late final TextEditingController _phoneCtrl =
      TextEditingController(text: widget.initialTargetPhone ?? '');
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (title.isEmpty) {
      _toast(context, 'Please enter a notification title', error: true);
      return;
    }
    if (body.isEmpty) {
      _toast(context, 'Please enter a message body', error: true);
      return;
    }
    if (!_isBroadcast && phone.isEmpty) {
      _toast(context, 'Please enter recipient phone number', error: true);
      return;
    }

    setState(() => _busy = true);
    try {
      await AdminService().sendNotification(
        title: title,
        body: body,
        target: _isBroadcast ? 'all' : phone,
        targetPhone: _isBroadcast ? null : phone,
      );
      if (!mounted) return;
      Navigator.pop(context);
      _toast(context, _isBroadcast ? 'Broadcast sent to all users' : 'Notification sent to $phone');
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

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Send Notification',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary(isDark),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Notification will be delivered to active user devices and logged in database.',
              style: TextStyle(color: AppColors.textMuted(isDark), fontSize: 12.5),
            ),
            const SizedBox(height: 16),

            // Target selector
            Row(
              children: [
                ChoiceChip(
                  label: const Text('All Users (Broadcast)'),
                  selected: _isBroadcast,
                  onSelected: _busy
                      ? null
                      : (s) {
                          if (s) setState(() => _isBroadcast = true);
                        },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Specific User'),
                  selected: !_isBroadcast,
                  onSelected: _busy
                      ? null
                      : (s) {
                          if (s) setState(() => _isBroadcast = false);
                        },
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (!_isBroadcast) ...[
              TextField(
                controller: _phoneCtrl,
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Recipient Phone Number',
                  hintText: 'e.g. 01813570430',
                  prefixIcon: Icon(Icons.phone_android_rounded),
                ),
              ),
              const SizedBox(height: 12),
            ],

            TextField(
              controller: _titleCtrl,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. Flash Seat Alert / Important Notice',
                prefixIcon: Icon(Icons.title_rounded),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _bodyCtrl,
              enabled: !_busy,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Message Body',
                hintText: 'Write your message details here...',
                prefixIcon: Icon(Icons.message_rounded),
              ),
            ),
            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: AppColors.primary,
                ),
                onPressed: _busy ? null : _send,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _busy ? 'Sending...' : (_isBroadcast ? 'Broadcast to All Users' : 'Send to User'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── User Activity Logs Tab & Sheet ──────────────────────────────────────────

Color _actionColor(String action) {
  final a = action.toUpperCase();
  if (a.contains('LOGIN') || a.contains('AUTH')) return const Color(0xFF3B82F6);
  if (a.contains('SEAT') || a.contains('FOUND') || a.contains('SUCCESS')) return const Color(0xFF10B981);
  if (a.contains('CREDIT') || a.contains('RECHARGE')) return const Color(0xFFF59E0B);
  if (a.contains('BOOK') || a.contains('RESERVE')) return const Color(0xFF8B5CF6);
  if (a.contains('FAIL') || a.contains('EXPIRE') || a.contains('BLOCK')) return const Color(0xFFEF4444);
  return Colors.grey;
}

IconData _actionIcon(String action) {
  final a = action.toUpperCase();
  if (a.contains('LOGIN')) return Icons.login_rounded;
  if (a.contains('LOGOUT')) return Icons.logout_rounded;
  if (a.contains('SEAT')) return Icons.chair_rounded;
  if (a.contains('CREDIT')) return Icons.bolt_rounded;
  if (a.contains('BOOK') || a.contains('RESERVE')) return Icons.confirmation_number_rounded;
  if (a.contains('EXPIRE')) return Icons.timer_off_rounded;
  return Icons.receipt_rounded;
}

class _UserLogsTab extends StatefulWidget {
  const _UserLogsTab();

  @override
  State<_UserLogsTab> createState() => _UserLogsTabState();
}

class _UserLogsTabState extends State<_UserLogsTab>
    with AutomaticKeepAliveClientMixin {
  late final Stream<List<AdminActivityLog>> _stream =
      AdminService().watchAllActivityLogs();
  final _search = TextEditingController();
  String _q = '';
  String _actionFilter = 'ALL';

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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search phone, action or details',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _q.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _search.clear();
                        setState(() => _q = '');
                      },
                    )
                  : null,
            ),
          ),
        ),
        // Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              _filterChip('ALL', isDark),
              const SizedBox(width: 6),
              _filterChip('LOGIN', isDark),
              const SizedBox(width: 6),
              _filterChip('CREDIT', isDark),
              const SizedBox(width: 6),
              _filterChip('SEATS', isDark),
              const SizedBox(width: 6),
              _filterChip('BOOKING', isDark),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: StreamBuilder<List<AdminActivityLog>>(
            stream: _stream,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Text(
                    'Error: ${snap.error}',
                    style: const TextStyle(color: AppColors.error),
                  ),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final logs = snap.data!.where((log) {
                if (_actionFilter != 'ALL' &&
                    !log.action.toUpperCase().contains(_actionFilter)) {
                  return false;
                }
                if (_q.isEmpty) return true;
                return log.phone.toLowerCase().contains(_q) ||
                    log.action.toLowerCase().contains(_q) ||
                    log.details.toLowerCase().contains(_q);
              }).toList();

              if (logs.isEmpty) {
                return Center(
                  child: Text(
                    'No activity logs found',
                    style: TextStyle(color: AppColors.textMuted(isDark)),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                itemCount: logs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _ActivityLogTile(
                  log: logs[i],
                  isDark: isDark,
                  showPhone: true,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String filter, bool isDark) {
    final selected = _actionFilter == filter;
    return ChoiceChip(
      label: Text(filter, style: const TextStyle(fontSize: 11)),
      selected: selected,
      onSelected: (_) => setState(() => _actionFilter = filter),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ActivityLogTile extends StatelessWidget {
  final AdminActivityLog log;
  final bool isDark;
  final bool showPhone;

  const _ActivityLogTile({
    required this.log,
    required this.isDark,
    this.showPhone = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = _actionColor(log.action);
    final icon = _actionIcon(log.action);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBg(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(isDark)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        log.action,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                    if (showPhone && log.phone.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        log.phone,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary(isDark),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      _fmtDate(log.timestamp),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textMuted(isDark),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  log.details.isNotEmpty ? log.details : 'No additional details',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: AppColors.textSecondary(isDark),
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

class _UserLogsSheet extends StatelessWidget {
  final AdminUser user;

  const _UserLogsSheet({required this.user});

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
      builder: (_) => _UserLogsSheet(user: user),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.history_rounded, color: AppColors.primary, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Activity Logs: ${user.displayName.isNotEmpty ? user.displayName : user.phone}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary(isDark),
                          ),
                        ),
                        Text(
                          '${user.phone} · Balance: ${user.credits} credits',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted(isDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Expanded(
                child: StreamBuilder<List<AdminActivityLog>>(
                  stream: AdminService().watchUserLogs(user.phone),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(
                        child: Text(
                          'Error loading logs: ${snap.error}',
                          style: const TextStyle(color: AppColors.error),
                        ),
                      );
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final logs = snap.data!;
                    if (logs.isEmpty) {
                      return Center(
                        child: Text(
                          'No activity logs recorded for this user yet.',
                          style: TextStyle(color: AppColors.textMuted(isDark)),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      itemCount: logs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _ActivityLogTile(
                        log: logs[i],
                        isDark: isDark,
                        showPhone: false,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
