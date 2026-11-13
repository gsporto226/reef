// Spike #76: one WebView2 instance, two Flutter Texture widgets. The plugin
// renders into a texture whose id is the controller's view id
// (WindowsInAppWebViewController.getViewId()), so a plain
// Texture(textureId: id) elsewhere mirrors the same live page.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Future<List<int>> pixels(WidgetTester t, GlobalKey key) async {
  final img = await t.runAsync(() async {
    final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final i = await b.toImage();
    return (await i.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });
  return img!.buffer.asUint8List();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('second Texture mirrors the live webview', (t) async {
    InAppWebViewController? c;
    final id = ValueNotifier<int?>(null);
    final a = GlobalKey(), b = GlobalKey();
    await t.pumpWidget(MaterialApp(
      home: Column(children: [
        RepaintBoundary(
          key: a,
          child: SizedBox(
            width: 200,
            height: 150,
            child: InAppWebView(
              initialData: InAppWebViewInitialData(
                data: '<body style="margin:0;background:#ff0000"></body>',
              ),
              onWebViewCreated: (ctl) {
                c = ctl;
                id.value = ctl.getViewId() as int;
              },
            ),
          ),
        ),
        RepaintBoundary(
          key: b,
          child: SizedBox(
            width: 200,
            height: 150,
            child: ValueListenableBuilder<int?>(
              valueListenable: id,
              builder: (_, v, _) =>
                  v == null ? const SizedBox() : Texture(textureId: v),
            ),
          ),
        ),
      ]),
    ));

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await t.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
        await t.pump();
      }
    }

    await settle();
    expect(id.value, isNotNull);
    final red = await pixels(t, b);
    expect(red.sublist(0, 4), [255, 0, 0, 255]);
    expect(await pixels(t, a), red);

    await t.runAsync(() => c!.evaluateJavascript(
        source: 'document.body.style.background="#0000ff"'));
    await settle();
    final blue = await pixels(t, b);
    expect(blue.sublist(0, 4), [0, 0, 255, 255]);
    expect(await pixels(t, a), blue);
  });
}
