import 'package:systock/core/widgets/action_colors.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart' as adaptive;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:go_router/go_router.dart';

enum PlatformGlyph {
  search,
  scanner,
  favorite,
  favoriteFilled,
  play,
  pause,
  add,
  remove,
  payment,
  back,
  logout,
}

class AdaptiveSearchField extends StatefulWidget {
  const AdaptiveSearchField({
    required this.hintText,
    required this.onChanged,
    this.controller,
    this.trailing,
    this.autofocus = false,
    super.key,
  });
  final String hintText;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final Widget? trailing;
  final bool autofocus;

  @override
  State<AdaptiveSearchField> createState() => _AdaptiveSearchFieldState();
}

class _AdaptiveSearchFieldState extends State<AdaptiveSearchField> {
  final _internalController = TextEditingController();
  TextEditingController get _controller =>
      widget.controller ?? _internalController;

  @override
  void dispose() {
    _internalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _controller,
        builder: (context, value, _) => Container(
          height: 44,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 14, right: 8),
                child: AdaptiveIcon(PlatformGlyph.search, size: 18),
              ),
              Expanded(
                child: adaptive.AdaptiveTextField(
                  controller: _controller,
                  autofocus: widget.autofocus,
                  placeholder: widget.hintText,
                  padding: EdgeInsets.zero,
                  decoration: InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  cupertinoDecoration: const BoxDecoration(
                    color: Colors.transparent,
                  ),
                  onChanged: widget.onChanged,
                ),
              ),
              if (value.text.isNotEmpty)
                IconButton(
                  tooltip: 'Limpar pesquisa'.localized(context),
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged('');
                  },
                ),
              ?widget.trailing,
              if (widget.trailing != null || value.text.isNotEmpty)
                const SizedBox(width: 4),
            ],
          ),
        ),
      );
}

class AdaptiveIcon extends StatelessWidget {
  const AdaptiveIcon(this.glyph, {this.size = 20, this.color, super.key});
  final PlatformGlyph glyph;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.windows) {
      const glyphs = {
        PlatformGlyph.search: '\uE721',
        PlatformGlyph.scanner: '\uE8A9',
        PlatformGlyph.favorite: '\uE734',
        PlatformGlyph.favoriteFilled: '\uE735',
        PlatformGlyph.play: '\uE768',
        PlatformGlyph.pause: '\uE769',
        PlatformGlyph.add: '\uE710',
        PlatformGlyph.remove: '\uE738',
        PlatformGlyph.payment: '\uE8C7',
        PlatformGlyph.back: '\uE72B',
        PlatformGlyph.logout: '\uE8AC',
      };
      return Text(
        glyphs[glyph]!,
        style: TextStyle(
          fontFamily: 'Segoe MDL2 Assets',
          fontSize: size,
          color: color ?? IconTheme.of(context).color,
        ),
      );
    }
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      const icons = {
        PlatformGlyph.search: CupertinoIcons.search,
        PlatformGlyph.scanner: CupertinoIcons.barcode_viewfinder,
        PlatformGlyph.favorite: CupertinoIcons.star,
        PlatformGlyph.favoriteFilled: CupertinoIcons.star_fill,
        PlatformGlyph.play: CupertinoIcons.play_fill,
        PlatformGlyph.pause: CupertinoIcons.pause_fill,
        PlatformGlyph.add: CupertinoIcons.plus,
        PlatformGlyph.remove: CupertinoIcons.minus,
        PlatformGlyph.payment: CupertinoIcons.creditcard_fill,
        PlatformGlyph.back: CupertinoIcons.chevron_back,
        PlatformGlyph.logout: CupertinoIcons.square_arrow_right,
      };
      return Icon(icons[glyph], size: size, color: color);
    }
    const icons = {
      PlatformGlyph.search: Icons.search_rounded,
      PlatformGlyph.scanner: Icons.qr_code_scanner_rounded,
      PlatformGlyph.favorite: Icons.star_border_rounded,
      PlatformGlyph.favoriteFilled: Icons.star_rounded,
      PlatformGlyph.play: Icons.play_arrow_rounded,
      PlatformGlyph.pause: Icons.pause_rounded,
      PlatformGlyph.add: Icons.add_rounded,
      PlatformGlyph.remove: Icons.remove_rounded,
      PlatformGlyph.payment: Icons.payments_rounded,
      PlatformGlyph.back: Icons.arrow_back_rounded,
      PlatformGlyph.logout: Icons.logout_rounded,
    };
    return Icon(icons[glyph], size: size, color: color);
  }
}

class AdaptiveIconButton extends StatelessWidget {
  const AdaptiveIconButton({
    required this.glyph,
    required this.onPressed,
    this.tooltip,
    this.selected = false,
    this.destructive = false,
    super.key,
  });
  final PlatformGlyph glyph;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool selected;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final icon = AdaptiveIcon(
      glyph,
      color: destructive
          ? (onPressed == null
                ? Theme.of(context).disabledColor
                : removalActionColor)
          : selected
          ? const Color(0xFFF4B740)
          : null,
    );
    if (platform == TargetPlatform.windows) {
      return Tooltip(
        message: tooltip ?? '',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: onPressed,
            child: SizedBox(width: 38, height: 38, child: Center(child: icon)),
          ),
        ),
      );
    }
    return adaptive.AdaptiveButton.child(
      onPressed: onPressed,
      enabled: onPressed != null,
      style: adaptive.AdaptiveButtonStyle.plain,
      size: adaptive.AdaptiveButtonSize.small,
      padding: const EdgeInsets.all(7),
      minSize: const Size(38, 38),
      child: icon,
    );
  }
}

class AdaptiveBackButton extends StatelessWidget {
  const AdaptiveBackButton({this.fallbackPath, super.key});
  final String? fallbackPath;

  @override
  Widget build(BuildContext context) => AdaptiveIconButton(
    glyph: PlatformGlyph.back,
    tooltip: 'Voltar'.localized(context),
    onPressed: () {
      if (context.canPop()) {
        context.pop();
        return;
      }
      context.go(fallbackPath ?? _parentOf(GoRouterState.of(context).uri.path));
    },
  );

  static String _parentOf(String path) {
    if (path.startsWith('/products/')) return '/products';
    if (path.startsWith('/inventory/counts/')) return '/inventory/counts';
    if (path.startsWith('/inventory/')) return '/inventory';
    if (path.startsWith('/purchases/')) return '/purchases';
    if (path.startsWith('/sales/')) return '/sales';
    if (path.startsWith('/settings/')) return '/settings';
    return '/dashboard';
  }
}

class AdaptivePrimaryButton extends StatelessWidget {
  const AdaptivePrimaryButton({
    required this.label,
    required this.onPressed,
    this.glyph,
    this.prominent = false,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final PlatformGlyph? glyph;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (glyph != null) ...[
          AdaptiveIcon(glyph!, size: 18, color: Colors.white),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: onPressed != null && prominent ? Colors.white : null,
              fontWeight: prominent ? FontWeight.w700 : null,
            ),
          ),
        ),
      ],
    );
    if (platform == TargetPlatform.windows) {
      final enabled = onPressed != null;
      return Material(
        color: enabled
            ? prominent
                  ? const Color(0xFF176BFF)
                  : Theme.of(context).colorScheme.primary
            : Theme.of(context).disabledColor,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: prominent ? 52 : 40,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withValues(alpha: .12)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              child: content,
            ),
          ),
        ),
      );
    }
    return adaptive.AdaptiveButton.child(
      onPressed: onPressed,
      enabled: onPressed != null,
      style: adaptive.AdaptiveButtonStyle.filled,
      size: adaptive.AdaptiveButtonSize.large,
      color: prominent ? const Color(0xFF176BFF) : null,
      borderRadius: BorderRadius.circular(
        platform == TargetPlatform.iOS ? 10 : 8,
      ),
      minSize: Size(double.infinity, prominent ? 52 : 44),
      child: content,
    );
  }
}
