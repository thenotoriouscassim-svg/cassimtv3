import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../widgets/conversation_panel.dart';
import '../widgets/input_bar.dart';
import '../widgets/status_bar_widget.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JarvisColors.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF101923), JarvisColors.background, Color(0xFF080D12)],
            stops: [0, .42, 1],
          ),
        ),
        child: const Column(
          children: [
            StatusBarWidget(),
            Expanded(child: ConversationPanel()),
            InputBar(),
          ],
        ),
      ),
    );
  }
}
