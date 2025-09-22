import 'package:flutter/material.dart';

Text sleekTitle(String text) => Text(
  text,
  style: const TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w700,
    fontSize: 18,
    letterSpacing: 0.6,
  ),
);

class GlassHeaderBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool centerTitle;

  const GlassHeaderBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.centerTitle = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: const Color(0x83F61146),
      elevation: 0,
      title: sleekTitle(title),
      centerTitle: centerTitle,
      leading: leading,
      actions: actions,
      foregroundColor: Colors.white,
    );
  }
}

class GlassFooterBar extends StatelessWidget {
  final String? rightText;
  final Widget? left;
  final Widget? right;

  const GlassFooterBar({super.key, this.rightText, this.left, this.right});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: const BoxDecoration(
        color: Color(0x83F61146),
        border: Border(top: BorderSide(color: Color(0x332A2F3A), width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Centered title ("Gym0" by default)
          Align(
            alignment: Alignment.center,
            child:
                left ??
                const Text(
                  'Gym0 - AnitronTech v1.0',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}
