import 'dart:math';

import 'package:flutter/material.dart';

/// 双击触发的「笑出鹅叫」红心 / emoji 飞屏（Kazumi 没有，本项目专属）
class FloatingHearts extends StatefulWidget {
  final int trigger;
  const FloatingHearts({super.key, required this.trigger});

  @override
  State<FloatingHearts> createState() => FloatingHeartsState();
}

class FloatingHeartsState extends State<FloatingHearts>
    with TickerProviderStateMixin {
  final List<_HeartParticle> _particles = [];
  final _rand = Random();

  @override
  void didUpdateWidget(FloatingHearts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger > oldWidget.trigger) {
      _spawn();
    }
  }

  void _spawn() {
    final c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    final p = _HeartParticle(
      controller: c,
      offsetX: 60.0 + _rand.nextDouble() * 60,
      emoji: ['🦢', '❤️', '🔥'][_rand.nextInt(3)],
    );
    c.addListener(() => setState(() {}));
    c.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _particles.remove(p);
        c.dispose();
        setState(() {});
      }
    });
    _particles.add(p);
    c.forward();
  }

  @override
  void dispose() {
    for (final p in _particles) {
      p.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: _particles.map((p) {
          final t = p.controller.value;
          return Positioned(
            right: p.offsetX,
            bottom: 60 + t * 200,
            child: Opacity(
              opacity: 1 - t,
              child: Transform.scale(
                scale: 0.6 + t * 1.2,
                child: Text(p.emoji, style: const TextStyle(fontSize: 28)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _HeartParticle {
  final AnimationController controller;
  final double offsetX;
  final String emoji;
  _HeartParticle({
    required this.controller,
    required this.offsetX,
    required this.emoji,
  });
}
