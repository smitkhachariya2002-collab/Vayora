import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

class VayoraAppBar extends StatelessWidget implements PreferredSizeWidget {
  const VayoraAppBar({super.key, required this.title, this.actions, this.leading, this.bottom});
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  @override
  Size get preferredSize => Size.fromHeight(AppSizes.toolbar + (bottom?.preferredSize.height ?? 0));
  @override
  Widget build(BuildContext context) => AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    leading: leading, actions: actions, bottom: bottom, flexibleSpace: const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.barGradient)));
}
class AppPage extends StatelessWidget {
  const AppPage({super.key, required this.body, this.title, this.actions, this.leading, this.bottom, this.fab, this.navigation});
  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? leading, bottom, fab, navigation;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: title == null ? null : VayoraAppBar(title: title!, leading: leading, actions: actions),
    body: SafeArea(top: title == null, bottom: navigation == null, child: body),
    bottomNavigationBar: navigation, bottomSheet: bottom, floatingActionButton: fab);
}
class PageWidth extends StatelessWidget {
  const PageWidth({super.key, required this.child, this.form = false});
  final Widget child;
  final bool form;
  @override
  Widget build(BuildContext context) => Align(heightFactor: 1, alignment: Alignment.topCenter, child: ConstrainedBox(
    constraints: BoxConstraints(maxWidth: form ? AppSizes.formWidth : AppSizes.contentWidth), child: child));
}
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.large = false});
  final bool large;
  @override
  Widget build(BuildContext context) => Semantics(label: AppBrand.name, image: true,
    child: Container(width: large ? AppSizes.logoLarge : AppSizes.logo, height: large ? AppSizes.logoLarge : AppSizes.logo,
      decoration: const BoxDecoration(gradient: AppColors.gradient, borderRadius: Radii.chipRadius),
      alignment: Alignment.center, child: const Text('V', style: TextStyle(
        fontSize: AppSizes.logoLetter, fontWeight: FontWeight.w700, color: AppColors.ink))));
}
class GlowHeader extends StatelessWidget {
  const GlowHeader({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(decoration: const BoxDecoration(gradient: AppColors.glow),
    child: Padding(padding: const EdgeInsets.symmetric(vertical: Gap.xl), child: child));
}
class CrownIcon extends StatelessWidget {
  const CrownIcon({super.key, this.color = AppColors.gold, this.size = AppSizes.icon});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: size, child: CustomPaint(painter: _CrownPainter(color)));
}
class _CrownPainter extends CustomPainter {
  const _CrownPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(size.width * .12, size.height * .25)
      ..lineTo(size.width * .32, size.height * .46)..lineTo(size.width * .5, size.height * .14)
      ..lineTo(size.width * .68, size.height * .46)..lineTo(size.width * .88, size.height * .25)
      ..lineTo(size.width * .78, size.height * .78)..lineTo(size.width * .22, size.height * .78)..close();
    canvas.drawPath(path, Paint()..color = color);
  }
  @override
  bool shouldRepaint(covariant _CrownPainter oldDelegate) => color != oldDelegate.color;
}
class CrownButton extends StatelessWidget {
  const CrownButton({super.key, required this.visible, required this.onPressed});
  final bool visible;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => visible ? IconButton(tooltip: 'Get Premium',
    onPressed: onPressed, icon: const CrownIcon()) : const SizedBox.shrink();
}
class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: Gap.s, vertical: Gap.xs),
    decoration: const BoxDecoration(color: AppColors.gold, borderRadius: Radii.chipRadius),
    child: const Row(mainAxisSize: MainAxisSize.min, children: [CrownIcon(color: AppColors.ink, size: AppSizes.iconSmall),
      SizedBox(width: Gap.xs), Text('Premium', style: TextStyle(fontSize: AppSizes.caption, fontWeight: FontWeight.w700, color: AppColors.ink))]));
}
class ThumbPill extends StatelessWidget {
  const ThumbPill(this.label, {super.key, this.icon});
  final String label;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: Gap.s, vertical: Gap.xs),
    decoration: const BoxDecoration(color: AppColors.pill, borderRadius: Radii.chipRadius),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: AppSizes.iconSmall), const SizedBox(width: Gap.xs)],
      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall)),
    ]));
}
class PlayOverlay extends StatelessWidget {
  const PlayOverlay({super.key, this.onPressed});
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Semantics(label: 'Play', button: onPressed != null,
    child: Container(decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.veil),
      child: IconButton(onPressed: onPressed, disabledColor: AppColors.text,
        iconSize: AppSizes.dialogIcon, icon: const Icon(Icons.play_arrow_rounded), color: AppColors.text)));
}
class NetThumb extends StatelessWidget {
  const NetThumb({super.key, this.url, this.overlays = const [], this.scrim = true});
  final String? url;
  final List<Widget> overlays;
  final bool scrim;
  @override
  Widget build(BuildContext context) => ClipRRect(borderRadius: Radii.cardRadius,
    child: AspectRatio(aspectRatio: AppSizes.videoRatio, child: Stack(fit: StackFit.expand, children: [
      const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.softGradient)),
      if (url != null && url!.isNotEmpty) Image.network(url!, fit: BoxFit.cover, cacheWidth: AppSizes.imageCacheWidth,
        gaplessPlayback: true, excludeFromSemantics: true,
        frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
          opacity: sync || frame != null ? 1 : 0,
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.fade, child: child),
        errorBuilder: (_, _, _) => const Center(child: Icon(Icons.movie_outlined, color: AppColors.muted, size: AppSizes.emptyIcon)))
      else const Center(child: Icon(Icons.movie_outlined, color: AppColors.muted, size: AppSizes.emptyIcon)),
      if (scrim) const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.scrim)),
      ...overlays,
    ])));
}
class ChannelAvatar extends StatelessWidget {
  const ChannelAvatar({super.key, required this.channel, this.radius = AppSizes.avatar});
  final Map<String, dynamic> channel;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final name = (channel['name'] as String? ?? AppBrand.name).trim();
    final url = channel['icon_url'] as String?;
    final letter = name.isEmpty ? 'V' : String.fromCharCode(name.runes.first).toUpperCase();
    final fallback = Center(child: Text(letter, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.ink)));
    return Container(width: radius * 2, height: radius * 2,
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.gradient),
      child: ClipOval(child: url != null && url.isNotEmpty
        ? Image.network(url, fit: BoxFit.cover, cacheWidth: AppSizes.avatarCacheWidth, gaplessPlayback: true,
            errorBuilder: (_, _, _) => fallback)
        : fallback));
  }
}
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.onSeeAll});
  final String title;
  final VoidCallback? onSeeAll;
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
    if (onSeeAll != null) TextButton(onPressed: onSeeAll, child: const Text('See all')),
  ]);
}
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.actionLabel, this.onAction});
  final IconData icon;
  final String title, message;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(padding: Gap.page, child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: AppSizes.emptyIcon, color: AppColors.muted), const SizedBox(height: Gap.l),
    Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
    const SizedBox(height: Gap.s), Text(message, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
    if (actionLabel != null && onAction != null) ...[const SizedBox(height: Gap.xl),
      GradientButton(label: actionLabel!, onPressed: onAction)],
  ]));
}
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.onRetry, this.message = "Couldn't load. Check your connection."});
  final VoidCallback onRetry;
  final String message;
  @override
  Widget build(BuildContext context) => EmptyState(icon: Icons.wifi_off_rounded, title: 'Let’s try that again',
    message: message, actionLabel: 'Try again', onAction: onRetry);
}
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, required this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  State<PressScale> createState() => _PressScaleState();
}
class _PressScaleState extends State<PressScale> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onTap, onTapDown: widget.onTap == null ? null : (_) => setState(() => pressed = true),
    onTapUp: widget.onTap == null ? null : (_) => setState(() => pressed = false), onTapCancel: widget.onTap == null ? null : () => setState(() => pressed = false),
    child: AnimatedScale(scale: pressed && !MediaQuery.disableAnimationsOf(context) ? AppSizes.pressedScale : AppSizes.restingScale,
      duration: AppMotion.press, child: widget.child));
}
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.onPressed, this.icon, this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  @override
  Widget build(BuildContext context) => Opacity(opacity: onPressed == null && !busy ? AppSizes.disabledOpacity : 1,
    child: DecoratedBox(decoration: const BoxDecoration(gradient: AppColors.gradient, borderRadius: Radii.buttonRadius),
      child: FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.transparent,
        disabledBackgroundColor: AppColors.transparent, disabledForegroundColor: AppColors.ink, foregroundColor: AppColors.ink),
        onPressed: busy ? null : onPressed,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
          if (busy) const SizedBox.square(dimension: AppSizes.spinner,
            child: CircularProgressIndicator(strokeWidth: AppSizes.focusStroke, color: AppColors.ink))
          else if (icon != null) Icon(icon),
          if (busy || icon != null) const SizedBox(width: Gap.s),
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ]))));
}
class SkeletonBlock extends StatefulWidget {
  const SkeletonBlock({super.key, this.height = AppSizes.mediaHero, this.width});
  final double height;
  final double? width;
  @override
  State<SkeletonBlock> createState() => _SkeletonBlockState();
}
class _SkeletonBlockState extends State<SkeletonBlock> with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(vsync: this, duration: AppMotion.shimmer)..repeat();
  @override
  void dispose() { animation.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => SizedBox(height: widget.height, width: widget.width,
    child: ClipRRect(borderRadius: Radii.cardRadius, child: AnimatedBuilder(animation: animation, builder: (context, child) =>
      DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment(MediaQuery.disableAnimationsOf(context) ? 0 : animation.value * 4 - 2, 0),
        end: const Alignment(2, 0), colors: const [AppColors.surface, AppColors.shimmer, AppColors.surface])), child: child))));
}
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 3});
  final int count;
  @override
  Widget build(BuildContext context) => Column(children: List.generate(count, (_) => const Padding(
    padding: EdgeInsets.only(bottom: Gap.l), child: SkeletonBlock())));
}
enum NoticeTone { success, warning, danger, neutral }
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.tone = NoticeTone.neutral});
  final String label;
  final NoticeTone tone;
  @override
  Widget build(BuildContext context) {
    final (foreground, background) = switch (tone) {
      NoticeTone.success => (AppColors.success, AppColors.successBg),
      NoticeTone.warning => (AppColors.warning, AppColors.warningBg),
      NoticeTone.danger => (AppColors.danger, AppColors.dangerBg),
      NoticeTone.neutral => (AppColors.muted, AppColors.surfaceHigh),
    };
    return Container(padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: Gap.xs),
      decoration: BoxDecoration(color: background, borderRadius: Radii.chipRadius),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: foreground)));
  }
}
class NoticeCard extends StatelessWidget {
  const NoticeCard({super.key, required this.title, required this.message, this.tone = NoticeTone.neutral, this.onTap});
  final String title, message;
  final NoticeTone tone;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => PressScale(onTap: onTap, child: Card(child: Padding(padding: const EdgeInsets.all(Gap.l),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(tone == NoticeTone.success ? Icons.check_circle_outline : tone == NoticeTone.warning ? Icons.schedule : Icons.info_outline,
        color: tone == NoticeTone.success ? AppColors.success : tone == NoticeTone.warning ? AppColors.warning : AppColors.muted),
      const SizedBox(width: Gap.m), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: Gap.xs),
        Text(message, style: Theme.of(context).textTheme.bodySmall)])),
      if (onTap != null) const Icon(Icons.chevron_right, color: AppColors.muted),
    ]))));
}
Future<bool> confirmAction(BuildContext context, {required String title, required String message,
    required String action, IconData icon = Icons.info_outline, bool destructive = false}) async {
  return await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
    icon: Icon(icon, size: AppSizes.dialogIcon, color: destructive ? AppColors.danger : AppColors.primary),
    title: Text(title, textAlign: TextAlign.center), content: Text(message, textAlign: TextAlign.center),
    actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Not now')),
      FilledButton(style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.white) : null,
        onPressed: () => Navigator.pop(dialog, true), child: Text(action))])) ?? false;
}
void showFeedback(BuildContext context, String message) {
  ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(message)));
}
String durationLabel(num? raw) {
  final seconds = (raw ?? 0).toInt();
  final minutes = seconds ~/ 60;
  return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
}
String compactNumber(num? number) {
  final value = number ?? 0;
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}m';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  return value.toString();
}
String storageLabel(num? raw) {
  final bytes = (raw ?? 0).toDouble();
  const names = ['B', 'KB', 'MB', 'GB', 'TB'];
  final index = bytes <= 0 ? 0 : (math.log(bytes) / math.log(1024)).floor().clamp(0, names.length - 1);
  final amount = bytes / math.pow(1024, index);
  return '${amount.toStringAsFixed(index == 0 || amount == amount.roundToDouble() ? 0 : 1)} ${names[index]}';
}
String shortDate(String? raw) {
  final date = DateTime.tryParse(raw ?? '')?.toLocal();
  if (date == null) return '';
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.square(dimension: AppSizes.icon, child: CustomPaint(painter: _GooglePainter()));
}
class _GooglePainter extends CustomPainter {
  const _GooglePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(size.width * .12, size.height * .12, size.width * .76, size.height * .76);
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = size.width * .18;
    const parts = [(AppColors.googleBlue, -.15, .65), (AppColors.googleGreen, .5, .8),
      (AppColors.googleYellow, 1.3, .4), (AppColors.googleRed, 1.7, .9)];
    for (final (color, start, sweep) in parts) {
      canvas.drawArc(rect, start * math.pi, sweep * math.pi, false, paint..color = color);
    }
    canvas.drawLine(Offset(size.width * .52, size.height * .5), Offset(size.width * .94, size.height * .5),
      paint..color = AppColors.googleBlue);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ExpandableCopy extends StatefulWidget {
  const ExpandableCopy(this.text,{super.key});
  final String text;
  @override
  State<ExpandableCopy> createState()=>_ExpandableCopyState();
}
class _ExpandableCopyState extends State<ExpandableCopy>{
  bool expanded=false;
  @override
  Widget build(BuildContext context)=>LayoutBuilder(builder:(context,limits){
    final style=Theme.of(context).textTheme.bodyLarge;
    final measurement=TextPainter(text:TextSpan(text:widget.text,style:style),maxLines:3,
      textDirection:Directionality.of(context),textScaler:MediaQuery.textScalerOf(context))..layout(maxWidth:limits.maxWidth);
    final truncated=measurement.didExceedMaxLines;measurement.dispose();
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(widget.text,maxLines:expanded?null:3,overflow:expanded?TextOverflow.visible:TextOverflow.ellipsis,style:style),
      if(truncated)TextButton(onPressed:()=>setState(()=>expanded=!expanded),child:Text(expanded?'less':'more')),
    ]);
  });
}
