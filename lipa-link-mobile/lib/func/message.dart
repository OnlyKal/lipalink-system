import 'package:flutter/material.dart';
import '../ui/widgets.dart';

/// Message bref en bas de l'écran (vert = succès, rouge = erreur).
void messageInfo(BuildContext context, String message, bool isError) {
  showAppSnack(context, message, error: isError);
}
