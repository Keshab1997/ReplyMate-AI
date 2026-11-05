import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  // No SDK, no network and no permission work at startup: the gate screen
  // renders first and everything optional initializes behind it.
  runApp(const ProviderScope(child: ReplyMateApp()));
}
