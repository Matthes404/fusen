import 'package:flutter/material.dart';

/// Begrenzt die Lesebreite.
///
/// Auf einem breiten Bildschirm läuft eine Zeile sonst über 1200 Pixel –
/// das liest niemand gern, und ein halbleerer Zettel sieht aus, als fehle
/// etwas. Der Inhalt bleibt deshalb in einer Spalte und rückt in die Mitte.
/// Breite der Inhaltsspalte. Kopfzeile und Liste teilen sie sich, damit
/// Überschrift und Zettel an derselben Kante beginnen.
const double pageMaxWidth = 940;

class PageBody extends StatelessWidget {
  const PageBody({
    required this.child,
    super.key,
    this.maxWidth = pageMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Der Seitenrand einer Ansicht.
///
/// Auf dem Handy ist Breite knapp – dort rücken die Zettel näher an den
/// Rand, auf dem Schreibtisch dürfen sie Luft haben.
double pageGutter(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 600 ? 16 : 24;
