import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Unified avatar widget used across the app.
/// Shows [photoUrl] if available, otherwise a coloured circle with the
/// first character of [displayName] as initials.
///
/// [size] is the diameter. [borderWidth] adds a coloured ring (default 0).
class UserAvatar extends StatelessWidget {
  final String? photoUrl;
  final String displayName;
  final double size;
  final double borderWidth;
  final Color? borderColor;

  const UserAvatar({
    super.key,
    this.photoUrl,
    required this.displayName,
    this.size = 40,
    this.borderWidth = 0,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final radius = size / 2;
    final effectiveBorder = borderWidth > 0
        ? Border.all(
            color: borderColor ?? context.colors.primary,
            width: borderWidth,
          )
        : null;

    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: effectiveBorder,
        ),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: photoUrl!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholder: (ctx, url) => _initials(context, radius),
            errorWidget: (ctx, url, err) => _initials(context, radius),
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: effectiveBorder,
      ),
      child: _initials(context, radius),
    );
  }

  Widget _initials(BuildContext context, double radius) {
    final letter =
        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: context.colors.primarySurface,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: radius * 0.7,
          fontWeight: FontWeight.w800,
          color: context.colors.primary,
          fontFamily: 'Inter',
        ),
      ),
    );
  }
}
