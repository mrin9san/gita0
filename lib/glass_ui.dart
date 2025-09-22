import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  const GlassCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.fromARGB(20, 255, 255, 255),
            Color.fromARGB(5, 255, 255, 255),
          ],
        ),
        border: Border.all(
          color: const Color.fromARGB(30, 255, 255, 255),
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color.fromARGB(120, 0, 0, 0),
            blurRadius: 10,
            offset: Offset(4, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            color: const Color.fromARGB(25, 0, 0, 0),
            child: child,
          ),
        ),
      ),
    );
  }
}

class ActionSpec {
  final IconData icon;
  final String label;
  final Color bg;
  final VoidCallback onTap;
  ActionSpec({
    required this.icon,
    required this.label,
    required this.bg,
    required this.onTap,
  });
}

class ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bg;
  final double circleSize;
  final double iconSize;
  final double labelGap;
  final VoidCallback onTap;

  const ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.bg,
    required this.circleSize,
    required this.iconSize,
    required this.labelGap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(circleSize / 2),
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: bg,
              shape: const CircleBorder(),
              elevation: 2,
              child: SizedBox(
                width: circleSize,
                height: circleSize,
                child: Icon(icon, size: iconSize, color: Colors.black),
              ),
            ),
            SizedBox(width: labelGap),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Exact same look/feel as your previous helper
Widget glassyField({
  required TextEditingController controller,
  required String label,
  int maxLines = 1,
  TextInputType? keyboardType,
  String? Function(String?)? validator,
  bool readOnly = false,
  VoidCallback? onTap,
  Widget? suffixIcon,
  ValueChanged<String>? onChanged,
}) {
  return TextFormField(
    controller: controller,
    readOnly: readOnly,
    onTap: onTap,
    onChanged: onChanged,
    maxLines: maxLines,
    keyboardType: keyboardType,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF2A2F3A)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF4F9CF9)),
      ),
      suffixIcon: suffixIcon,
    ),
    validator: validator,
  );
}

/// Exact same dropdown look
Widget glassDropdown<T>({
  required String label,
  required T? value,
  required List<T> items,
  required ValueChanged<T?> onChanged,
}) {
  return DropdownButtonFormField<T>(
    value: value,
    items: items
        .map(
          (e) => DropdownMenuItem<T>(
            value: e,
            child: Text(
              e.toString(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        )
        .toList(),
    onChanged: onChanged,
    style: const TextStyle(color: Colors.white),
    dropdownColor: const Color(0xFF111214),
    iconEnabledColor: Colors.white70,
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF2A2F3A)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF4F9CF9)),
      ),
    ),
  );
}
