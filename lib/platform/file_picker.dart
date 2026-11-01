import 'dart:convert';
import 'dart:io';

/// Neither kdialog nor zenity is installed.
class FilePickerUnavailable implements Exception {
  const FilePickerUnavailable();

  @override
  String toString() => 'Install kdialog or zenity to pick files.';
}

/// Asks the user to pick files with the desktop's own dialog: kdialog
/// (KDE), or zenity when kdialog is missing. Empty when cancelled.
Future<List<String>> pickFiles({required String title}) async {
  final home = Platform.environment['HOME'] ?? '/';
  final dialogs = [
    (
      'kdialog',
      [
        '--title',
        title,
        '--multiple',
        '--separate-output',
        '--getopenfilename',
        home,
      ],
    ),
    (
      'zenity',
      ['--file-selection', '--multiple', '--separator=\n', '--title=$title'],
    ),
  ];
  for (final (command, arguments) in dialogs) {
    final ProcessResult result;
    try {
      result = await Process.run(command, arguments);
    } on ProcessException {
      continue; // Not installed: try the next one.
    }
    // Both exit with 1 when the user cancels.
    return result.exitCode == 0 ? parsePickedFiles('${result.stdout}') : [];
  }
  throw const FilePickerUnavailable();
}

/// The dialogs print one path per line.
List<String> parsePickedFiles(String output) => [
  for (final line in const LineSplitter().convert(output))
    if (line.trim().isNotEmpty) line,
];
