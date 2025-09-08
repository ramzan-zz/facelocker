// lib/widgets/device_online_strip.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/device_presence_service.dart';

class DeviceOnlineStrip extends StatelessWidget {
  const DeviceOnlineStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Consumer<DevicePresenceService>(
          builder: (_, svc, __) {
            final list = svc.devices;
            if (list.isEmpty) {
              return Text('No devices configured',
                  style: TextStyle(color: scheme.onSurfaceVariant));
            }
            return Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: list
                  .map((d) => _DevicePill(
                        label: d.label,
                        online: d.online,
                      ))
                  .toList(),
            );
          },
        ),
      ),
    );
  }
}

class _DevicePill extends StatelessWidget {
  const _DevicePill({required this.label, required this.online});
  final String label;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = online ? Colors.greenAccent : scheme.error;
    final bg = online
        ? Colors.green.withOpacity(0.16)
        : scheme.error.withOpacity(0.14);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: online ? Colors.greenAccent.withOpacity(0.55) : scheme.error,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BlinkingDot(color: color, online: online),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: online ? scheme.onSurface : scheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            online ? 'online' : 'offline',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot({required this.color, required this.online});
  final Color color;
  final bool online;

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t =
            widget.online ? (0.6 + 0.4 * (0.5 - (_c.value - 0.5).abs())) : 1.0;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.online ? widget.color : widget.color.withOpacity(0.8),
            shape: BoxShape.circle,
            boxShadow: widget.online
                ? [
                    BoxShadow(
                      color: widget.color.withOpacity(0.55),
                      blurRadius: 8 * t,
                      spreadRadius: 0.5 * t,
                    ),
                  ]
                : [],
          ),
        );
      },
    );
  }
}
