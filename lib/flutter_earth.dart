library flutter_earth;

import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:vector_math/vector_math_64.dart' hide Colors;

/// Mercator projection
const double maxLatitude = 85.05112877980659 * math.pi / 180;

Offset latLonToPoint(double latitude, double longitude) {
  final x = 0.5 + longitude / (2.0 * math.pi);
  double y;
  if (latitude > maxLatitude || latitude < -maxLatitude) {
    y = 0.5 - latitude / math.pi;
  } else {
    final sinlat = math.sin(latitude);
    y = 0.5 - math.log((1 + sinlat) / (1 - sinlat)) / (4.0 * math.pi);
  }
  return Offset(x, y);
}

LatLon pointToLatLon(double x, double y) {
  final longitude = (x - 0.5) * (2.0 * math.pi);
  final latitude = 2.0 * math.atan(math.exp(math.pi - 2.0 * math.pi * y)) - math.pi / 2.0;
  return LatLon(latitude, longitude);
}

/// Cartesian coordinates
Vector3 latLonToVector3(LatLon latLon) {
  final x = math.cos(latLon.latitude) * math.cos(latLon.longitude);
  final y = math.cos(latLon.latitude) * math.sin(latLon.longitude);
  final z = math.sin(latLon.latitude);
  return Vector3(x, y, z);
}

LatLon vector3ToLatLon(Vector3 v) {
  final lat = math.asin(v.z);
  var lon = math.atan2(v.y, v.x);
  return LatLon(lat, lon);
}

LatLon quaternionToLatLon(Quaternion q) {
  final v = Vector3(0, 0, -1.0);
  q.inverted().rotate(v);
  v.normalize();
  return LatLon(math.asin(v.z), math.atan2(v.y, v.x));
}

class LatLon {
  LatLon(this.latitude, this.longitude);
  double latitude;
  double longitude;
  @override
  String toString() => 'LatLon(${((latitude ?? 0) * 180 / math.pi).toStringAsFixed(2)}, ${((longitude ?? 0) * 180 / math.pi).toStringAsFixed(2)})';
}

class Triangle {
  Triangle(this.point0, this.point1, this.point2);
  int point0;
  int point1;
  int point2;
}

class Mesh {
  Mesh(this.positions, this.textureCoordinates, this.triangleIndices, this.x, this.y, this.sumOfZ);
  List<Vector3> positions;
  List<Offset> textureCoordinates;
  List<Triangle> triangleIndices;
  double x;
  double y;
  double sumOfZ;
}

typedef TileCallback = void Function(Tile tile);

enum TileStatus {
  clear,
  pending,
  fetching,
  ready,
  error,
}

class Tile {
  Tile(this.x, this.y, this.z, {this.image, this.future});
  int x;
  int y;

  /// zoom level
  int z;
  TileStatus status = TileStatus.clear;
  ui.Image image;
  Future<ui.Image> future;
}

class FlutterEarth extends StatefulWidget {
  FlutterEarth({
    Key key,
    this.url,
    this.radius,
    this.subdivisions,
    this.showAxis = false,
    this.onTileStart,
    this.onTileEnd,
  }) : super(key: key);
  final String url;
  final double radius;
  final int subdivisions;
  final bool showAxis;
  final TileCallback onTileStart;
  final TileCallback onTileEnd;

  @override
  _FlutterEarthState createState() => _FlutterEarthState();
}

class _FlutterEarthState extends State<FlutterEarth> with TickerProviderStateMixin {
  double width;
  double height;
  double zoom;
  double _lastZoom;
  Offset _lastFocalPoint;

  final double _radius = 256 / (2 * math.pi);
  double get radius => _radius * math.pow(2, zoom);
  int get zoomLevel => zoom.round().clamp(0, maxZoom);
  List<Vector3> vertices;
  List<Offset> textureCoordinates;
  Quaternion quaternion = Quaternion.identity();
  Quaternion _lastQuaternion;
  AnimationController rotationXController;
  Animation<double> rotationXAnimation;
  AnimationController rotationYController;
  Animation<double> rotationYAnimation;
  AnimationController zoomController;
  Animation<double> zoomAnimation;

  String _info = '';

  final double tileWidth = 256;
  final double tileHeight = 256;
  final int maxZoom = 21;
  List<HashMap<int, Tile>> tiles;

  Vector3 canvasPointToVector3(Offset point) {
    final x = point.dx - width / 2;
    final y = point.dy - height / 2;
    var z = radius * radius - x * x - y * y;
    if (z < 0) z = 0;
    z = -math.sqrt(z);
    return Vector3(x, y, z);
  }

  String getTileURL(int x, int y, int z) {
    return widget.url.replaceAll('{z}', '$z').replaceAll('{x}', '$x').replaceAll('{y}', '$y');
  }

  Future<Tile> loadTileImage(Tile tile) async {
    tile.status = TileStatus.pending;
    final url = getTileURL(tile.x, tile.y, tile.z);
    if (widget.onTileStart != null) widget.onTileStart(tile);
    if (tile.status == TileStatus.ready) return tile;

    final c = Completer<ui.Image>();
    final networkImage = NetworkImage(url);
    final imageStream = networkImage.resolve(ImageConfiguration());
    imageStream.addListener(
      ImageStreamListener((ImageInfo imageInfo, bool synchronousCall) {
        c.complete(imageInfo.image);
      }),
    );
    tile.image = await c.future;
    tile.status = TileStatus.ready;
    if (widget.onTileEnd != null) widget.onTileEnd(tile);
    setState(() {});
    return tile;
  }

  Tile getTile(int x, int y, int z) {
    final key = (x << 32) + y;
    var tile = tiles[z][key];
    if (tile == null) {
      tile = Tile(x, y, z);
      tiles[z][key] = tile;
    }
    if (tile.status == TileStatus.clear) {
      loadTileImage(tile);
    }

    if (tile.status != TileStatus.ready) {
      for (var i = 1; i < maxZoom; i++) {
        var z1 = (i % 2 == 1) ? z + i ~/ 2 + 1 : z - i ~/ 2;
        if (z1 >= 0 && z1 < tiles.length) {
          final x1 = (x * math.pow(2, z1 - z)).toInt();
          final y1 = (y * math.pow(2, z1 - z)).toInt();
          final key1 = (x1 << 32) + y1;
          final tile1 = tiles[z1][key1];
          if (tile1?.status == TileStatus.ready) return tile1;
        }
      }
    }
    return tile;
  }

  bool tileObservable(int x, int y, Rect bounds) {
    final scale = math.pow(2.0, zoomLevel);
    final points = [Offset(0, 0), Offset(0, 1), Offset(1, 1), Offset(1, 0), Offset(0, 0.5), Offset(0.5, 1), Offset(1, 0.5), Offset(0.5, 0.5)];
    for (var p in points) {
      final x0 = (x + p.dx) / scale;
      final y0 = (y + p.dy) / scale;
      var latLon = pointToLatLon(x0, y0);
      final v = latLonToVector3(latLon)..scale(radius);
      quaternion.rotate(v);

      if (bounds.contains(Offset(v.x, v.y))) return true;
    }
    return false;
  }

  List<Offset> clipTiles(double visibleWidth, double visibleHeight, double radius) {
    final list = List<Offset>();
    final scale = math.pow(2.0, zoomLevel);
    final latlon = quaternionToLatLon(quaternion);
    final point = latLonToPoint(latlon.latitude, latlon.longitude) * scale;
    final x0 = point.dx.toInt();
    final y0 = point.dy.toInt();
    final bounds = Rect.fromLTWH(-visibleWidth / 2, -visibleHeight / 2, visibleWidth, visibleHeight);
    final maxK = 10;
    final observed = HashMap<int, int>();

    for (var k = 0; k < scale; k++) {
      for (var y = y0 - k; y <= y0 + k; y++) {
        for (var x = x0 - k; x <= x0 + k; x++) {
          if (x == x0 - k || x == x0 + k || y == y0 - k || y == y0 + k) {
            var x1 = x.toDouble();
            if (x1 >= scale) x1 %= scale;
            if (x1 < 0) x1 = scale - (-x1) % scale;
            var y1 = y.toDouble();
            if (y1 >= scale) y1 %= scale;
            if (y1 < 0) y1 = scale - (-y1) % scale;

            if (x1 < 0 || y1 < 0 || x1 >= scale || y1 >= scale) {
              continue;
            }
            final latlng = pointToLatLon((x1 + 0.5) / scale, (y1 + 0.5) / scale);
            final v = latLonToVector3(latlng)..scale(radius);
            quaternion.rotate(v);
            // if (v.z >= 0)
            if (tileObservable(x1.toInt(), y1.toInt(), bounds)) {
              final key = (x1.toInt() << 32) + y1.toInt();
              if (!observed.containsKey(key)) {
                observed[key] = 0;
                list.add(Offset(x1.toDouble(), y1.toDouble()));
              }
            }
          }
        }
      }
      if (k > maxK) break;
    }
    return list;
  }

  Mesh buildTileMesh(Offset offset, double tileWidth, double tileHeight, int subdivisions, double width, double height, double radius) {
    final positions = List<Vector3>();
    final textureCoordinates = List<Offset>();
    final triangleIndices = List<Triangle>();
    var sumOfZ = 0.0;

    for (var j = 0; j <= subdivisions; j++) {
      final y0 = (offset.dy + tileHeight * j / subdivisions) / height;
      for (var i = 0; i <= subdivisions; i++) {
        final x0 = (offset.dx + tileWidth * i / subdivisions) / width;
        var latLon = pointToLatLon(x0, y0);
        final v = latLonToVector3(latLon)..scale(radius);
        quaternion.rotate(v);
        positions.add(v);
        textureCoordinates.add(Offset(tileWidth * i / subdivisions, tileHeight * j / subdivisions));
        sumOfZ += v.z;
      }
    }
    for (var j = 0; j < subdivisions; j++) {
      var k1 = j * (subdivisions + 1);
      var k2 = k1 + subdivisions + 1;
      for (var i = 0; i < subdivisions; i++) {
        triangleIndices.add(Triangle(k1, k2, k1 + 1));
        triangleIndices.add(Triangle(k1 + 1, k2, k2 + 1));
        k1++;
        k2++;
      }
    }

    triangleIndices.sort((Triangle a, Triangle b) {
      final az = positions[a.point0].z + positions[a.point1].z + positions[a.point2].z;
      final bz = positions[b.point0].z + positions[b.point1].z + positions[b.point2].z;
      return bz.compareTo(az);
    });

    return Mesh(positions, textureCoordinates, triangleIndices, offset.dx, offset.dy, sumOfZ);
  }

  void drawXYZAxis(Canvas canvas, Size size, [double length = 50, double width = 5]) {
    // Draw X Y Z axis
    final positions = List<Offset>();
    final positions3 = List<Vector3>();
    final height = math.sqrt(width * width * (1 - 0.25));
    width /= 2;
    positions3..add(Vector3(0, 0, 0));
    positions3.add(Vector3(length, 0, 0));
    positions3.add(Vector3(length, width, height));
    positions3.add(Vector3(length, -width, height));
    positions3.add(Vector3(0, length, 0));
    positions3.add(Vector3(width, length, height));
    positions3.add(Vector3(-width, length, height));
    positions3.add(Vector3(0, 0, length));
    positions3.add(Vector3(width, height, length));
    positions3.add(Vector3(-width, height, length));
    final triangles = [
      Triangle(0, 1, 2),
      Triangle(0, 1, 3),
      Triangle(0, 2, 3),
      Triangle(0, 4, 5),
      Triangle(0, 4, 6),
      Triangle(0, 5, 6),
      Triangle(0, 7, 8),
      Triangle(0, 7, 9),
      Triangle(0, 8, 9),
    ];

    for (var v in positions3) {
      quaternion.rotate(v);
    }

    triangles.sort((Triangle a, Triangle b) {
      final az = positions3[a.point0].z + positions3[a.point1].z + positions3[a.point2].z;
      final bz = positions3[b.point0].z + positions3[b.point1].z + positions3[b.point2].z;
      return bz.compareTo(az);
    });

    for (var v in positions3) {
      positions.add(Offset(v.x, v.y));
    }

    final indices = List<int>();
    for (var t in triangles) {
      indices..add(t.point0)..add(t.point1)..add(t.point2);
    }

    final vertices = ui.Vertices(
      ui.VertexMode.triangleFan,
      positions,
      colors: [Colors.yellow, Colors.red, Colors.red, Colors.red, Colors.green, Colors.green, Colors.green, Colors.blue, Colors.blue, Colors.blue],
      indices: indices,
    );
    if (widget.showAxis) canvas.drawVertices(vertices, BlendMode.src, Paint());
  }

  void drawTiles(Canvas canvas, Size size) {
    final tiles = clipTiles(width, height, radius);
    final meshList = List<Mesh>();
    final maxWidth = tileWidth * (1 << zoomLevel);
    final maxHeight = tileHeight * (1 << zoomLevel);

    for (var t in tiles) {
      final mesh = buildTileMesh(
        Offset(t.dx * tileWidth, t.dy * tileHeight),
        tileWidth,
        tileHeight,
        widget.subdivisions,
        maxWidth,
        maxHeight,
        radius,
      );
      meshList.add(mesh);
    }

    meshList.sort((Mesh a, Mesh b) {
      return b.sumOfZ.compareTo(a.sumOfZ);
    });

    for (var mesh in meshList) {
      final positions = List<Offset>();
      final indices = List<int>();

      for (var p in mesh.positions) {
        positions.add(Offset(p.x, p.y));
      }

      for (var t in mesh.triangleIndices) {
        indices..add(t.point0)..add(t.point1)..add(t.point2);
      }

      final tile = getTile(mesh.x ~/ tileWidth, mesh.y ~/ tileHeight, zoomLevel);
      if (tile.status == TileStatus.ready) {
        //Is zoomed tile?
        final zoomedTextureCoordinates = List<Offset>();
        if (tile.z != zoomLevel) {
          for (var p in mesh.textureCoordinates) {
            var x = (mesh.x + p.dx) * math.pow(2, tile.z - zoomLevel) - tile.x * tileWidth;
            var y = (mesh.y + p.dy) * math.pow(2, tile.z - zoomLevel) - tile.y * tileHeight;
            zoomedTextureCoordinates.add(Offset(x, y));
          }
        }

        final vertices = ui.Vertices(
          ui.VertexMode.triangles,
          positions,
          textureCoordinates: (tile.z != zoomLevel) ? zoomedTextureCoordinates : mesh.textureCoordinates,
          indices: indices,
        );

        final paint = Paint();
        Float64List matrix4 = new Matrix4.identity().storage;
        final shader = ImageShader(tile.image, TileMode.mirror, TileMode.mirror, matrix4);
        paint.shader = shader;
        canvas.drawVertices(vertices, BlendMode.src, paint);
      }
    }
    drawXYZAxis(canvas, size);
  }

  void _updateInfo() {
    final latLon = quaternionToLatLon(quaternion);
    _info = 'lat:${(latLon.latitude * 180 / math.pi).toStringAsFixed(2)}, lon:${(latLon.longitude * 180 / math.pi).toStringAsFixed(2)}, zoom:${zoom.toStringAsFixed(2)}';
    // final p = latLonToPoint(latLon.latitude, latLon.longitude);
    // final l = pointToLatLon(p.dx, p.dy);
    // final p2 = latLonToPoint(l.latitude, l.longitude);
    // _info += '''

    // $p, $l, $p2''';
  }

  void _handleScaleStart(ScaleStartDetails details) {
    rotationXController.stop();
    rotationXController.stop();
    _lastZoom = zoom;
    _lastFocalPoint = details.focalPoint;
    _lastQuaternion = quaternion;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    zoom = _lastZoom + math.log(details.scale) / math.ln2;

    Quaternion q;
    // final RenderBox box = context.findRenderObject();
    // final oldCoord = canvasPointToVector3(box.globalToLocal(_lastFocalPoint));
    // final newCoord = canvasPointToVector3(box.globalToLocal(details.focalPoint));
    // q = Quaternion.fromTwoVectors(newCoord, oldCoord);

    final offset = details.focalPoint - _lastFocalPoint;
    q = Quaternion.axisAngle(Vector3(0, 1.0, 0), offset.dx / radius);
    q *= Quaternion.axisAngle(Vector3(1.0, 0, 0), -offset.dy / radius);

    q *= Quaternion.axisAngle(Vector3(0, 0, 1.0), -details.rotation);
    quaternion = _lastQuaternion * q; //quaternion A * B is not equal to B * A

    _updateInfo();
    setState(() {});
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _lastQuaternion = quaternion;
    final a = -300;
    var v = details.velocity.pixelsPerSecond.dx * 0.3;
    var t = (v / a).abs() * 1000;
    var s = (v.sign * 0.5 * v * v / a) / radius;
    rotationXController.duration = Duration(milliseconds: t.toInt());
    rotationXAnimation = Tween<double>(begin: 0, end: -s).animate(CurveTween(curve: Curves.decelerate).animate(rotationXController));
    rotationXController
      ..value = 0
      ..forward();

    // v = details.velocity.pixelsPerSecond.dy * 0.3;
    // t = (v / a).abs() * 1000;
    // s = (v.sign * 0.5 * v * v / a) / radius;
    // rotationYController.duration = Duration(milliseconds: t.toInt());
    // rotationYAnimation = Tween<double>(begin: 0, end: -s).animate(CurveTween(curve: Curves.decelerate).animate(rotationYController));
    // rotationYController
    //   ..value = 0
    //   ..forward();
  }

  void _handleDoubleTap() {
    _lastZoom = zoom;
    zoomController.duration = Duration(milliseconds: 1000);
    zoomAnimation = Tween<double>(begin: 0, end: 1).animate(zoomController);
    zoomController
      ..value = 0
      ..forward();
  }

  @override
  void initState() {
    super.initState();
    tiles = List(maxZoom + 1);
    for (var i = 0; i <= maxZoom; i++) tiles[i] = HashMap<int, Tile>();

    zoom = math.log(widget.radius / _radius) / math.ln2;
    rotationXController = AnimationController(vsync: this)
      ..addListener(() {
        setState(() {
          final q = Quaternion.axisAngle(Vector3(0, 1.0, 0), rotationXAnimation.value);
          quaternion = _lastQuaternion * q;
        });
      });
    rotationYController = AnimationController(vsync: this)
      ..addListener(() {
        setState(() {
          final q = Quaternion.axisAngle(Vector3(0, 1.0, 0), rotationYAnimation.value);
          quaternion = _lastQuaternion * q;
        });
      });
    zoomController = AnimationController(vsync: this)
      ..addListener(() {
        setState(() {
          if (_lastZoom + zoomAnimation.value > maxZoom)
            zoom = maxZoom.toDouble();
          else
            zoom = _lastZoom + zoomAnimation.value;
          _updateInfo();
        });
      });
  }

  @override
  void dispose() {
    rotationXController.dispose();
    rotationYController.dispose();
    zoomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        width = constraints.maxWidth;
        height = constraints.maxHeight;
        return GestureDetector(
          onScaleStart: _handleScaleStart,
          onScaleUpdate: _handleScaleUpdate,
          onScaleEnd: _handleScaleEnd,
          onDoubleTap: _handleDoubleTap,
          child: Stack(
            children: <Widget>[
              Center(
                child: CustomPaint(
                  painter: SpherePainter(this),
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                ),
              ),
              widget.showAxis ? Text(_info) : Container(),
            ],
          ),
        );
      },
    );
  }
}

class SpherePainter extends CustomPainter {
  const SpherePainter(this.state);

  final _FlutterEarthState state;

  @override
  void paint(Canvas canvas, Size size) {
    var stopwatch = Stopwatch()..start();
    canvas.translate(size.width / 2, size.height / 2);
    state.drawTiles(canvas, size);
    stopwatch.stop();
    print('paint() executed in ${stopwatch.elapsed.inMilliseconds}');
  }

  // We should repaint whenever the board changes, such as board.selected.
  @override
  bool shouldRepaint(SpherePainter oldDelegate) {
    return true;
  }
}
