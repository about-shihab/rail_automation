import 'package:flutter/material.dart';
import '../models/seat_type.dart';

class SeatBadge extends StatelessWidget {
  final SeatType seat;
  final bool isSelected;
  final VoidCallback? onTap;

  const SeatBadge({
    super.key,
    required this.seat,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasSeats = seat.isAvailable;

    final bgColor = isDark
        ? (hasSeats ? const Color(0xFF064E3B).withValues(alpha: 0.4) : const Color(0xFF1E293B))
        : (hasSeats ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC));

    final borderColor = isSelected
        ? Colors.amber
        : (hasSeats
            ? const Color(0xFF10B981)
            : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)));

    final titleColor = isDark
        ? (hasSeats ? Colors.white : Colors.white60)
        : (hasSeats ? const Color(0xFF065F46) : const Color(0xFF64748B));

    final fareColor = isDark
        ? (hasSeats ? Colors.tealAccent : Colors.white38)
        : (hasSeats ? const Color(0xFF047857) : const Color(0xFF94A3B8));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  seat.type,
                  style: TextStyle(
                    color: titleColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: hasSeats
                        ? (isDark ? const Color(0xFF10B981) : const Color(0xFF059669))
                        : Colors.red.withValues(alpha: isDark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${seat.seatCounts.online}',
                    style: TextStyle(
                      color: hasSeats ? Colors.white : Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '৳${seat.fare}',
              style: TextStyle(
                color: fareColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
