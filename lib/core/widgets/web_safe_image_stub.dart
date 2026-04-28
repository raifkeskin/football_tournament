import 'package:flutter/material.dart';

Widget buildWebSafeImage(
  BuildContext context, {
  required String url,
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  BorderRadius? borderRadius,
  bool isCircle = false,
  double? fallbackIconSize,
}) {
  final trimmed = url.trim();
  final fallback = Icon(
    Icons.shield,
    color: Colors.grey,
    size: fallbackIconSize,
  );

  if (trimmed.isEmpty) {
    return SizedBox(
      width: width,
      height: height,
      child: Center(child: fallback),
    );
  }

  final img = Image.network(
    trimmed,
    width: width,
    height: height,
    fit: fit,
    errorBuilder: (_, _, _) => SizedBox(
      width: width,
      height: height,
      child: Center(child: fallback),
    ),
  );

  if (isCircle) {
    return ClipOval(child: img);
  }
  if (borderRadius != null) {
    return ClipRRect(borderRadius: borderRadius, child: img);
  }
  return img;
}

