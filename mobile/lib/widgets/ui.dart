import 'package:flutter/material.dart';

import '../theme.dart';

/// Shared building blocks so every screen looks the same.

/// A friendly "nothing here" block: icon, title, one line of help and an optional button.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.actionLabel, this.onAction});
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: Tokens.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(24)),
            child: Icon(icon, color: Tokens.primary, size: 32),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: Tokens.muted, fontSize: 13, height: 1.4)),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: onAction, icon: const Icon(Icons.add, size: 18), label: Text(actionLabel!)),
          ],
        ]),
      );
}

/// The small grey bar at the top of a bottom sheet.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});
  @override
  Widget build(BuildContext context) =>
      Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Tokens.border, borderRadius: BorderRadius.circular(2))));
}

/// Square avatar with the first letter of a name on the brand gradient.
class InitialAvatar extends StatelessWidget {
  const InitialAvatar({super.key, required this.name, this.size = 44});
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(gradient: Tokens.gradient, borderRadius: BorderRadius.circular(size * .3)),
        child: Text(name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * .42)),
      );
}

/// A tappable row for choosing a file: icon, label, what is chosen, and a clear button.
class PickTile extends StatelessWidget {
  const PickTile({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap, this.onClear, this.chosen = false, this.badge});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final bool chosen;
  final String? badge;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            decoration: BoxDecoration(
              color: Tokens.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: chosen ? Tokens.primary.withValues(alpha: .6) : Tokens.border),
            ),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: Tokens.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
                child: Icon(chosen ? Icons.check_rounded : icon, color: chosen ? Tokens.success : Tokens.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                    if (badge != null)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: Tokens.border, borderRadius: BorderRadius.circular(8)),
                        child: Text(badge!, style: const TextStyle(color: Tokens.muted, fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                  ]),
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Tokens.muted, fontSize: 12)),
                ]),
              ),
              if (chosen && onClear != null)
                IconButton(onPressed: onClear, icon: const Icon(Icons.close_rounded, size: 18, color: Tokens.muted), tooltip: 'Remove')
              else
                const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.chevron_right_rounded, color: Tokens.muted)),
            ]),
          ),
        ),
      );
}

String fmtDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60);
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// 16:9 video card image: thumbnail (or a placeholder), duration chip and a Premium badge.
class VideoThumb extends StatelessWidget {
  const VideoThumb({super.key, this.url, this.seconds, this.premium = false, this.radius = 14, this.aspectRatio = 16 / 9});
  final String? url;
  final int? seconds;
  final bool premium;
  final double radius;
  final double aspectRatio;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(fit: StackFit.expand, children: [
            Container(
              decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1B376A), Color(0xFF116C70)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
              child: const Center(child: Icon(Icons.play_circle_outline_rounded, color: Colors.white38, size: 44)),
            ),
            if (url != null) Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            if (premium)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: .65), borderRadius: BorderRadius.circular(8)),
                  child: const Tooltip(message: 'Premium', child: Icon(Icons.workspace_premium, color: Tokens.gold, size: 14)),
                ),
              ),
            if (seconds != null && seconds! > 0)
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: .7), borderRadius: BorderRadius.circular(6)),
                  child: Text(fmtDuration(Duration(seconds: seconds!)), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ),
          ]),
        ),
      );
}

/// Shared poster grid across Home, Explore, channel pages and suggestions.
class VideoGrid extends StatelessWidget {
  const VideoGrid({super.key, required this.itemCount, required this.itemBuilder, this.shrinkWrap = false, this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24)});
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool shrinkWrap;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
    final available = box.maxWidth - padding.horizontal;
    final columns = available < 280 ? 2 : (available / 140).floor().clamp(3, 6);
    const gap = 8.0;
    final width = (available - gap * (columns - 1)) / columns;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return GridView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
      padding: padding,
      itemCount: itemCount,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns, crossAxisSpacing: gap, mainAxisSpacing: 12,
        mainAxisExtent: width * 1.5 + 12 + 52 * scale,
      ),
      itemBuilder: itemBuilder,
    );
  });
}

class VideoCard extends StatelessWidget {
  const VideoCard({super.key, required this.title, required this.onTap, this.channel = '', this.url, this.premium = false, this.seconds});
  final String title, channel;
  final String? url;
  final bool premium;
  final int? seconds;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true, label: 'Play $title',
    child: InkWell(
      borderRadius: BorderRadius.circular(12), onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        VideoThumb(url: url, seconds: seconds, premium: premium, radius: 16, aspectRatio: 2 / 3),
        const SizedBox(height: 8),
        SizedBox(height: MediaQuery.textScalerOf(context).scale(14) * 2.6, child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 1.3, fontWeight: FontWeight.w600))),
        const SizedBox(height: 3),
        Text(channel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, height: 1.3, color: Tokens.muted)),
      ]),
    ),
  );
}

