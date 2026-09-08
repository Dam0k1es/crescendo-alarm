import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

class PageAboutpage extends StatelessWidget {
  const PageAboutpage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'About WakeyWakey',
          style: TextStyle(fontSize: 24),
        ),
      ),
      body: FutureBuilder<String>(
        future: loadMarkdownFile('text/Privacy.md'),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Markdown(
              data: snapshot.data!,
              selectable: true,
            );
          } else if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          } else {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
        },
      ),
    );
  }
}

Future<String> loadMarkdownFile(String fileName) async {
  final markdownFile = await rootBundle.loadString('assets/$fileName');
  return markdownFile;
}
