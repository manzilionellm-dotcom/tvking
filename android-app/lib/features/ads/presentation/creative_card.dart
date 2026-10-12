import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../simple_home/data/announcement_repository.dart';
import '../domain/campaign_creative.dart';
import '../../mobile_services/data/mobile_services.dart';

/// Relief natif léger : aucune vidéo, aucun moteur WebGL, aucun son.
/// Le mouvement est borné à dix secondes et s'arrête hors premier plan.
class CreativeCard extends StatefulWidget {
  const CreativeCard({
    super.key,
    required this.announcement,
    required this.onClose,
    required this.onOpen,
  });
  final Announcement announcement;
  final VoidCallback onClose, onOpen;
  @override
  State<CreativeCard> createState() => _CreativeCardState();
}

class _CreativeCardState extends State<CreativeCard>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion;
  bool _started = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MobileServices.instance.addListener(_preferenceChanged);
    _motion = AnimationController(
      vsync: this,
      duration: Duration(
        seconds: widget.announcement.creative!.durationSeconds,
      ),
    );
  }

  void _preferenceChanged() {
    if (!MobileServices.instance.allowVisualMotion) _motion.stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !MobileServices.instance.allowVisualMotion ||
        !widget.announcement.creative!.motion) {
      _motion.stop();
      return;
    }
    if (!_started) {
      _started = true;
      _motion.forward();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _motion.stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MobileServices.instance.removeListener(_preferenceChanged);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Announcement a = widget.announcement;
    final CampaignCreative c = a.creative!;
    final Color accent = switch (c.palette) {
      'ice' => AppColors.info,
      'gold' => AppColors.editorialCream,
      _ => AppColors.accent,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: RepaintBoundary(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: AppColors.surface,
            border: Border.all(color: accent.withValues(alpha: .35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                height: 120,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                        child: AnimatedBuilder(
                          animation: _motion,
                          builder: (BuildContext context, Widget? child) {
                            final double wave = math.sin(
                              _motion.value * math.pi * 4,
                            );
                            return Stack(
                              children: <Widget>[
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _HaloPainter(
                                      accent,
                                      c.template,
                                      wave,
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 42),
                                    child: Transform(
                                      alignment: Alignment.center,
                                      transform: Matrix4.identity()
                                        ..setEntry(3, 2, .0018)
                                        ..rotateY(wave * .22 - .15)
                                        ..rotateZ(wave * .06 - .12)
                                        ..translate(0.0, wave * 5),
                                      child: SizedBox(
                                        width: 86,
                                        height: 86,
                                        child: c.imageUrl.isEmpty
                                            ? _Gem(
                                                accent: accent,
                                                prism: c.template == 'prism',
                                              )
                                            : CachedNetworkImage(
                                                imageUrl: c.imageUrl,
                                                memCacheWidth: 256,
                                                maxWidthDiskCache: 512,
                                                fit: BoxFit.contain,
                                                errorWidget: (_, __, ___) =>
                                                    _Gem(
                                                      accent: accent,
                                                      prism:
                                                          c.template == 'prism',
                                                    ),
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    Positioned(
                      left: 18,
                      top: 16,
                      child: Text(
                        'PUBLICITÉ',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.textSecondary,
                          letterSpacing: 1.8,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 3,
                      top: 3,
                      child: IconButton(
                        tooltip: MaterialLocalizations.of(context)
                            .closeButtonTooltip,
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (c.badge.isNotEmpty)
                      Text(
                        c.badge,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: accent,
                          letterSpacing: 1.5,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(a.title, style: AppTextStyles.headlineMedium),
                    const SizedBox(height: 8),
                    Text(
                      a.body,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (a.url.isNotEmpty && a.cta.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: AppColors.voidSurface,
                          ),
                          onPressed: widget.onOpen,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    a.cta,
                                    style: AppTextStyles.button.copyWith(
                                      color: AppColors.voidSurface,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.north_east_rounded),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Gem extends StatelessWidget {
  const _Gem({required this.accent, required this.prism});
  final Color accent;
  final bool prism;
  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: prism ? math.pi / 4 : .1,
    child: Container(
      margin: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(prism ? 8 : 22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            AppColors.textPrimary,
            accent,
            AppColors.surfaceOverlay,
          ],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.voidSurface.withValues(alpha: .5),
            offset: const Offset(12, 16),
            blurRadius: 12,
          ),
        ],
        border: Border.all(color: AppColors.textPrimary.withValues(alpha: .5)),
      ),
    ),
  );
}

class _HaloPainter extends CustomPainter {
  const _HaloPainter(this.color, this.template, this.wave);
  final Color color;
  final String template;
  final double wave;
  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width - 85, 63);
    final Paint halo = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          color.withValues(alpha: .24),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: 130));
    canvas.drawCircle(center, 130, halo);
    final Paint ring = Paint()
      ..color = color.withValues(alpha: .55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = template == 'orbit' ? 5 : 1;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-.45 + wave * .08);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 162, height: 52),
      ring,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HaloPainter old) =>
      wave != old.wave || color != old.color || template != old.template;
}
