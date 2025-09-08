// lib/widgets/powered_by_footer.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

class PoweredByFooter extends StatefulWidget {
  const PoweredByFooter({super.key, this.height = 36, this.onTap});

  /// Footer height. Keep this in sync with the bottom padding you add in MaterialApp.builder.
  final double height;
  final VoidCallback? onTap;

  @override
  State<PoweredByFooter> createState() => _PoweredByFooterState();
}

class _PoweredByFooterState extends State<PoweredByFooter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Base colors for a soft, modern gradient bar
    final baseA = scheme.surface.withOpacity(0.92);
    final baseB = Color.alphaBlend(scheme.primary.withOpacity(0.08), baseA);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap ?? () => _showAbout(context),
        child: SizedBox(
          height: widget.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Animated gradient background (subtle, modern)
              AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  final t = _ctrl.value;
                  // Slide the gradient slowly for a living feel.
                  final begin = Alignment(-1 + 2 * t, 0);
                  final end = Alignment(1 + 2 * t, 0);
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: begin,
                        end: end,
                        colors: [baseA, baseB, baseA],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                      border: Border(
                        top: BorderSide(color: scheme.outlineVariant),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.shadow.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // Moving sheen highlight (very subtle)
              AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  final t = _ctrl.value;
                  // Position the sheen from left -> right
                  final x = -0.6 + t * 2.2; // overshoot so it exits smoothly
                  return Align(
                    alignment: Alignment(x.clamp(-1.0, 1.0), 0),
                    child: IgnorePointer(
                      child: FractionallySizedBox(
                        widthFactor: 0.26,
                        heightFactor: 1.0,
                        child: Transform.rotate(
                          angle: -8 * math.pi / 180,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white.withOpacity(0.00),
                                  Colors.white.withOpacity(0.08),
                                  Colors.white.withOpacity(0.00),
                                ],
                                stops: const [0.0, 0.5, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              // Content: icon + “Powered by” + gradient brand text
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Icon(Icons.bolt_rounded,
                          size: 16, color: scheme.onSurfaceVariant),
                      Text(
                        'Powered by',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                      _GradientText(
                        'Syncronose',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                        gradient: LinearGradient(
                          colors: [
                            scheme.primary,
                            scheme.tertiary,
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.workspace_premium_rounded,
                  color: scheme.primary, size: 28),
              const SizedBox(height: 8),
              Text(
                'FaceLocker',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Powered by Syncronose',
                style: TextStyle(
                  fontSize: 13.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Secure, fast, and flexible locker access using on-device capture, cloud recognition, and Cloud control.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Close'),
                onPressed: () => Navigator.of(ctx).maybePop(),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Simple gradient text helper (no extra packages).
class _GradientText extends StatelessWidget {
  const _GradientText(this.text,
      {required this.gradient, this.style, this.maxLines});

  final String text;
  final Gradient gradient;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => gradient
          .createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
      blendMode: BlendMode.srcIn,
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: (style ?? const TextStyle()).copyWith(color: Colors.white),
      ),
    );
  }
}
