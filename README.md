# flutter_earth

[![pub package](https://img.shields.io/pub/v/flutter_earth.svg)](https://pub.dev/packages/flutter_earth)
A Flutter earth widget.

## Getting Started

Add flutter_earth as a dependency in your pubspec.yaml file.

```yaml
dependencies:
  flutter_earth: ^0.0.4
```

```dart
import 'package:flutter_earth/flutter_earth.dart';
... ...
  
@override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FlutterEarth(
          url: 'http://mt0.google.com/vt/lyrs=y&hl=en&x={x}&y={y}&z={z}',
          radius: 180,
        ),
      ),
    );
  }
```

## Screenshot

![screenshot](https://github.com/zesage/flutter_earth/raw/master/resource/screenshot.gif)
