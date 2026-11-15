import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../widgets/conversation_panel.dart';
import '../widgets/input_bar.dart';
import '../widgets/status_bar_widget.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: JarvisColors.background,
      body: SafeArea(
        child: Column(
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
