import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../theme.dart';

/// Die Farbe eines Projekts mit seinem Anfangsbuchstaben – erkennbarer als
/// ein Punkt und auf einen Blick zu unterscheiden, auch bei ähnlichen Farben.
class ProjectAvatar extends StatelessWidget {
  const ProjectAvatar({required this.project, super.key, this.size = 22});

  final ProjectRow project;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Color(project.color);
    final letter = project.name.trim().isEmpty
        ? '?'
        : project.name.trim().characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontFamily: fusenFontFamily,
          fontSize: size * 0.52,
          fontWeight: FontWeight.w800,
          height: 1,
          color: Colors.white,
        ),
      ),
    );
  }
}
