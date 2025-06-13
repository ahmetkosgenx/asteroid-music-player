import 'package:asteroid/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const Map<String, MaterialColor> materialColors = {
    'Red': Colors.red,
    'Pink': Colors.pink,
    'Purple': Colors.purple,
    'Deep Purple': Colors.deepPurple,
    'Indigo': Colors.indigo,
    'Blue': Colors.blue,
    'Light Blue': Colors.lightBlue,
    'Cyan': Colors.cyan,
    'Teal': Colors.teal,
    'Green': Colors.green,
    'Light Green': Colors.lightGreen,
    'Lime': Colors.lime,
    'Yellow': Colors.yellow,
    'Amber': Colors.amber,
    'Orange': Colors.orange,
    'Deep Orange': Colors.deepOrange,
    'Brown': Colors.brown,
    'Grey': Colors.grey,
    'Blue Grey': Colors.blueGrey,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Consumer<ThemeProvider>(
              builder: (context, themeProvider, child) {
                return _ThemeSettings(themeProvider: themeProvider);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeSettings extends StatefulWidget {
  final ThemeProvider themeProvider;
  const _ThemeSettings({required this.themeProvider});

  @override
  State<_ThemeSettings> createState() => _ThemeSettingsState();
}

class _ThemeSettingsState extends State<_ThemeSettings> {
  bool showColorPicker = false;

  @override
  Widget build(BuildContext context) {
    final themeProvider = widget.themeProvider;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: const Text('Theme Mode'),
          trailing: DropdownButton<CustomThemeMode>(
            value: themeProvider.themeMode,
            onChanged: (CustomThemeMode? newValue) {
              if (newValue != null) {
                themeProvider.setThemeMode(newValue);
              }
            },
            items: const [
              DropdownMenuItem(
                value: CustomThemeMode.system,
                child: Text('System'),
              ),
              DropdownMenuItem(
                value: CustomThemeMode.light,
                child: Text('Light'),
              ),
              DropdownMenuItem(
                value: CustomThemeMode.dark,
                child: Text('Dark'),
              ),
              DropdownMenuItem(
                value: CustomThemeMode.amoled,
                child: Text('AMOLED (True Black)'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          icon: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: themeProvider.primarySwatch,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade400),
            ),
          ),
          label: const Text('Set Primary Color'),
          onPressed: () => setState(() => showColorPicker = !showColorPicker),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 250),
          crossFadeState: showColorPicker ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: SettingsScreen.materialColors.entries.map((entry) {
                final isSelected = themeProvider.primarySwatch == entry.value;
                return GestureDetector(
                  onTap: () {
                    themeProvider.setPrimarySwatch(entry.value);
                    setState(() => showColorPicker = false);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: entry.value, width: 4)
                          : null,
                    ),
                    child: CircleAvatar(
                      backgroundColor: entry.value,
                      radius: 20,
                      child: isSelected
                          ? Icon(Icons.check, color: Colors.white, size: 20)
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          secondChild: const SizedBox.shrink(),
        ),
        const SizedBox(height: 24),
        // Add more settings here as needed
      ],
    );
  }
}