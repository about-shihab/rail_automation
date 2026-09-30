import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Design Tokens ──────────────────────────────────────────────────────────

class AppColors {
  // Brand palette
  static const primary = Color(0xFF00C896);
  static const primaryDark = Color(0xFF00A07A);
  static const primaryGlow = Color(0x3300C896);
  static const accent = Color(0xFF3DEFE9);
  static const gold = Color(0xFFFBBF24);

  // Dark mode surfaces
  static const darkBg = Color(0xFF060D1A);
  static const darkSurface = Color(0xFF0B1628);
  static const darkCard = Color(0xFF0F1F35);
  static const darkCardBorder = Color(0xFF1E3A55);
  static const darkInput = Color(0xFF0A1728);
  static const darkInputBorder = Color(0xFF1A3048);

  // Light mode surfaces
  static const lightBg = Color(0xFFF0F5FF);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightCardBorder = Color(0xFFDDE8F5);
  static const lightInput = Color(0xFFF5F9FF);
  static const lightInputBorder = Color(0xFFCBDCF0);

  // Text
  static const darkTextPrimary = Color(0xFFEDF2FF);
  static const darkTextSecondary = Color(0xFF8AA4C0);
  static const darkTextMuted = Color(0xFF91A5BC);
  static const lightTextPrimary = Color(0xFF0A1628);
  static const lightTextSecondary = Color(0xFF3A5270);
  static const lightTextMuted = Color(0xFF53677F);

  // Status
  static const success = Color(0xFF00C896);
  static const warning = Color(0xFFFBBF24);
  static const error = Color(0xFFFF4757);
  static const info = Color(0xFF60A5FA);

  // AppBar
  static const appBarGradientStart = Color(0xFF003D2B);
  static const appBarGradientEnd = Color(0xFF006649);

  // Helpers
  static Color scaffoldBg(bool isDark) => isDark ? darkBg : lightBg;
  static Color surface(bool isDark) => isDark ? darkSurface : lightSurface;
  static Color cardBg(bool isDark) => isDark ? darkCard : lightCard;
  static Color cardBorder(bool isDark) => isDark ? darkCardBorder : lightCardBorder;
  static Color textPrimary(bool isDark) => isDark ? darkTextPrimary : lightTextPrimary;
  static Color textSecondary(bool isDark) => isDark ? darkTextSecondary : lightTextSecondary;
  static Color textMuted(bool isDark) => isDark ? darkTextMuted : lightTextMuted;
  static Color inputFill(bool isDark) => isDark ? darkInput : lightInput;
  static Color inputBorder(bool isDark) => isDark ? darkInputBorder : lightInputBorder;

  // Legacy
  static const appBarGreen = Color(0xFF006649);
}

// ─── Theme Data ─────────────────────────────────────────────────────────────

class AppThemes {
  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.darkSurface,
      error: AppColors.error,
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onSurface: AppColors.darkTextPrimary,
    ),
    scaffoldBackgroundColor: AppColors.darkBg,
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: AppColors.darkSurface,
      indicatorColor: AppColors.primary.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkSurface,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: AppColors.darkTextPrimary),
      titleTextStyle: TextStyle(
        color: AppColors.darkTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkInput,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.darkInputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.darkInputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      labelStyle: const TextStyle(color: AppColors.darkTextSecondary),
    ),
    cardTheme: CardThemeData(
      color: AppColors.darkCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.darkCardBorder),
      ),
    ),
  );

  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: AppColors.primaryDark,
      secondary: AppColors.accent,
      surface: AppColors.lightSurface,
      error: AppColors.error,
      onPrimary: Colors.white,
      onSurface: AppColors.lightTextPrimary,
    ),
    scaffoldBackgroundColor: AppColors.lightBg,
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: AppColors.lightSurface,
      indicatorColor: AppColors.primary.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.lightSurface,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: AppColors.lightTextPrimary),
      titleTextStyle: TextStyle(
        color: AppColors.lightTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryDark,
        side: const BorderSide(color: AppColors.primaryDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.lightInput,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.lightInputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.lightInputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryDark, width: 2),
      ),
      labelStyle: const TextStyle(color: AppColors.lightTextSecondary),
    ),
    cardTheme: CardThemeData(
      color: AppColors.lightCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.lightCardBorder),
      ),
    ),
  );
}

// ─── Reusable Widgets ────────────────────────────────────────────────────────

/// Gradient primary button
class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final double height;

  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: onPressed == null || loading
                ? [Colors.grey.shade600, Colors.grey.shade700]
                : [AppColors.primary, AppColors.primaryDark],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: onPressed != null && !loading
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: isDark ? 0.35 : 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  )
                ]
              : null,
        ),
        child: ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18, color: Colors.black87),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Standard card container
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(18);
    final border = BorderSide(color: borderColor ?? AppColors.cardBorder(isDark));
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ],
      ),
      child: Material(
        color: AppColors.cardBg(isDark),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: border,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: padding ?? const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Status badge chip
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── App bar ────────────────────────────────────────────────────────────────

/// Header backdrop shared by every top bar: deep green gradient, fine
/// concentric rings, a soft top sheen and a glowing hairline along the base.
/// Use as `flexibleSpace` in any AppBar / SliverAppBar.
class NavBackdrop extends StatelessWidget {
  final double radius;
  const NavBackdrop({super.key, this.radius = 22});

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.vertical(bottom: Radius.circular(radius));
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.appBarGradientStart,
            AppColors.appBarGradientEnd,
            Color(0xFF00876A),
          ],
          stops: [0.0, 0.62, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.appBarGradientStart.withValues(alpha: 0.32),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              right: -56,
              top: -84,
              child: _ring(230, 0.07),
            ),
            Positioned(
              right: 4,
              top: -40,
              child: _ring(120, 0.06),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.09),
                      Colors.white.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.6],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 1.5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.accent.withValues(alpha: 0),
                      AppColors.accent.withValues(alpha: 0.55),
                      AppColors.primary.withValues(alpha: 0.55),
                      AppColors.primary.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _ring(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: alpha), width: 1.2),
        ),
      );
}

/// Frosted square icon button for app bars (optionally with a status dot).
class NavAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool dot;
  final Color? color;

  const NavAction({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.dot = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
    );
    Widget btn = Material(
      color: Colors.white.withValues(alpha: 0.12),
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 20, color: color ?? Colors.white),
              if (dot)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.appBarGradientEnd, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (tooltip != null) btn = Tooltip(message: tooltip!, child: btn);
    return Center(
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: btn),
    );
  }
}

/// Frosted pill for app bars: credits, language, "Guide"…
/// Pass [tint] to colour it (gold for credits, amber for warnings).
class NavPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? iconColor;
  final Color? tint;
  final VoidCallback? onTap;

  const NavPill({
    super.key,
    required this.label,
    this.icon,
    this.iconColor,
    this.tint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = tint;
    final shape = StadiumBorder(
      side: BorderSide(
        color: t != null ? t.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.18),
      ),
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: t != null ? t.withValues(alpha: 0.20) : Colors.white.withValues(alpha: 0.12),
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 15, color: iconColor ?? Colors.white),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      letterSpacing: 0.2,
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
}

/// Credits pill used in every app bar. Turns amber with a "Buy" hint at zero.
class NavCreditPill extends StatelessWidget {
  final int credits;
  final VoidCallback? onTap;
  const NavCreditPill({super.key, required this.credits, this.onTap});

  @override
  Widget build(BuildContext context) {
    final zero = credits <= 0;
    final c = zero ? AppColors.warning : AppColors.gold;
    return NavPill(
      icon: Icons.bolt_rounded,
      iconColor: c,
      tint: c,
      label: zero ? '0 • Buy' : '$credits',
      onTap: onTap,
    );
  }
}

/// Rounded app-mark tile for the leading slot of an app bar.
class NavLogo extends StatelessWidget {
  final IconData icon;
  final double size;
  const NavLogo({super.key, this.icon = Icons.train_rounded, this.size = 38});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.26),
                Colors.white.withValues(alpha: 0.08),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: Icon(icon, color: Colors.white, size: size * 0.54),
        ),
      ),
    );
  }
}

/// Top bar used across the app: one consistent look for every screen.
///
/// * [icon] shows a logo tile in the leading slot (tab screens).
/// * With no [leading] or [icon], a glass back button appears when the
///   screen can be popped.
/// * [subtitleWidget] replaces [subtitle] for richer status lines.
class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final IconData? icon;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;

  const GradientAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.icon,
    this.actions,
    this.leading,
    this.bottom,
  });

  static const double _toolbar = 64;

  @override
  Size get preferredSize =>
      Size.fromHeight(_toolbar + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    Widget? lead = leading;
    if (lead == null && icon != null && !canPop) {
      lead = NavLogo(icon: icon!);
    } else if (lead == null && canPop) {
      lead = NavAction(
        icon: Icons.arrow_back_ios_new_rounded,
        onTap: () => Navigator.maybePop(context),
      );
    }

    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: Colors.white),
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      toolbarHeight: _toolbar,
      centerTitle: false,
      flexibleSpace: const NavBackdrop(),
      leading: lead,
      leadingWidth: lead == null ? 0 : 54,
      titleSpacing: lead == null ? 18 : 8,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          if (subtitleWidget != null)
            Padding(padding: const EdgeInsets.only(top: 2), child: subtitleWidget!)
          else if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
      actions: [...?actions, const SizedBox(width: 10)],
      bottom: bottom,
    );
  }
}
