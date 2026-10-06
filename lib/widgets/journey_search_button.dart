import 'package:flutter/material.dart';

class JourneySearchButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback? onPressed;
  const JourneySearchButton({
    super.key,
    required this.label,
    required this.icon,
    this.loading = false,
    this.onPressed,
  });
  @override
  State<JourneySearchButton> createState() => _JourneySearchButtonState();
}

class _JourneySearchButtonState extends State<JourneySearchButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    return Listener(
      onPointerDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed && enabled ? .98 : 1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 140),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 60),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: enabled
                  ? const [
                      Color(0xFF00AF87),
                      Color(0xFF00765F),
                      Color(0xFF005747),
                    ]
                  : const [Color(0xFF66847D), Color(0xFF526D67)],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: .24)),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: const Color(0xFF008C6C).withValues(alpha: .24),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                    ),
                  ]
                : null,
          ),
          child: ElevatedButton(
            onPressed: enabled ? widget.onPressed : null,
            style: ElevatedButton.styleFrom(
              textStyle: const TextStyle(fontFamily: 'Roboto'),
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white70,
              shadowColor: Colors.transparent,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: widget.loading
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(widget.icon, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
