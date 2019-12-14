library flutter_earth;

import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/material.dart';
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

/// Cartesian coordinate conversions
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

/// Quaternion conversions
LatLon quaternionToLatLon(Quaternion q) {
  final euler = quaternionToEulerAngles(q);
  return eulerAnglesToLatLon(euler);
}

Quaternion latLonToQuaternion(LatLon latLon) {
  final euler = latLonToEulerAngles(latLon);
  return eulerAnglesToQuaternion(euler);
}

/// Fixed Quaternion.setFromTwoVectors from 'vector_math_64/quaternion.dart'.
Quaternion quaternionFromTwoVectors(Vector3 a, Vector3 b) {
  final Vector3 v1 = a.normalized();
  final Vector3 v2 = b.normalized();

  final double c = math.max(-1, math.min(1, v1.dot(v2)));
  double angle = math.acos(c);
  Vector3 axis = v1.cross(v2);
  if (axis.length == 0) axis = Vector3(1.0, 0.0, 0.0);

  return Quaternion.axisAngle(axis, angle);
}

/// Fixed Quaternion.axis from 'vector_math_64/quaternion.dart'.
Vector3 quaternionAxis(Quaternion q) {
  final _qStorage = q.storage;
  final double den = 1.0 - (_qStorage[3] * _qStorage[3]);
  if (den == 0) return new Vector3(1.0, 0.0, 0.0);

  final double scale = 1.0 / math.sqrt(den);
  return new Vector3(_qStorage[0] * scale, _qStorage[1] * scale, _qStorage[2] * scale);
}

/// Euler Angles
EulerAngles quaternionToEulerAngles(Quaternion q) {
  final _qStorage = q.storage;
  final _x = _qStorage[0];
  final _y = _qStorage[1];
  final _z = _qStorage[2];
  final _w = _qStorage[3];

  final roll = math.atan2(2 * (_w * _z + _x * _y), 1 - 2 * (_z * _z + _x * _x));
  final pitch = math.asin(math.max(-1, math.min(1, 2 * (_w * _x - _y * _z))));
  final yaw = math.atan2(2 * (_w * _y + _z * _x), 1 - 2 * (_x * _x + _y * _y));

  return EulerAngles(yaw, pitch, roll);
}

Quaternion eulerAnglesToQuaternion(EulerAngles euler) {
  return Quaternion.euler(euler.yaw, euler.pitch, euler.roll);
}

LatLon eulerAnglesToLatLon(EulerAngles euler) {
  return LatLon(-euler.pitch, -euler.yaw);
}

EulerAngles latLonToEulerAngles(LatLon latLon) {
  return EulerAngles(-latLon.longitude, -latLon.latitude, 0);
}

class EulerAngles {
  double yaw;
  double pitch;
  double roll;
  EulerAngles(this.yaw, this.pitch, this.roll);
  EulerAngles clone() => EulerAngles(yaw, pitch, roll);
  void scale(double arg) {
    yaw *= arg;
    pitch *= arg;
    roll *= arg;
  }

  EulerAngles inRadians() => EulerAngles(radians(yaw), radians(pitch), radians(roll));
  EulerAngles inDegrees() => EulerAngles(degrees(yaw), degrees(pitch), degrees(roll));
  @override
  String toString() => 'pitch:${pitch.toStringAsFixed(4)}, yaw:${yaw.toStringAsFixed(4)}, roll:${roll.toStringAsFixed(4)}';
}

class LatLon {
  LatLon(this.latitude, this.longitude);
  double latitude;
  double longitude;
  LatLon inRadians() => LatLon(radians(latitude), radians(longitude));
  LatLon inDegrees() => LatLon(degrees(latitude), degrees(longitude));
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

typedef TileCallback = void Function(Tile tile);
typedef void MapCreatedCallback(FlutterEarthController controller);
typedef void CameraPositionCallback(LatLon latLon, double zoom);

class FlutterEarth extends StatefulWidget {
  FlutterEarth({
    Key key,
    this.url,
    this.radius,
    this.subdivisions,
    this.onMapCreated,
    this.onCameraMove,
    this.onTileStart,
    this.onTileEnd,
  }) : super(key: key);
  final String url;
  final double radius;
  final int subdivisions;
  final TileCallback onTileStart;
  final TileCallback onTileEnd;
  final MapCreatedCallback onMapCreated;
  final CameraPositionCallback onCameraMove;

  @override
  _FlutterEarthState createState() => _FlutterEarthState();
}

class _FlutterEarthState extends State<FlutterEarth> with TickerProviderStateMixin {
  FlutterEarthController _controller;
  double width;
  double height;
  double zoom;
  double _lastZoom;
  Offset _lastFocalPoint;
  Quaternion _lastQuaternion;
  Vector3 _lastRotationAxis;
  double _lastGestureScale;
  double _lastGestureRatation;
  int _lastGestureTime = 0;

  final double _radius = 256 / (2 * math.pi);
  double get radius => _radius * math.pow(2, zoom);
  int get zoomLevel => zoom.round().clamp(0, maxZoom);
  LatLon get position => quaternionToLatLon(quaternion);
  EulerAngles get eulerAngles => quaternionToEulerAngles(quaternion);

  Quaternion quaternion = Quaternion.identity();
  AnimationController animController;
  Animation<double> panAnimation;
  Animation<double> riseAnimation;
  Animation<double> zoomAnimation;
  double _panCurveEnd = 0;

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

  LatLon canvasVector3ToLatLon(Vector3 v) {
    final q = Quaternion(-0.5, -0.5, 0.5, 0.5) * quaternion;
    q.inverted().rotate(v);
    v.normalize();
    return vector3ToLatLon(v);
  }

  Future<Tile> loadTileImage(Tile tile) async {
    tile.status = TileStatus.pending;
    final url = widget.url.replaceAll('{z}', '${tile.z}').replaceAll('{x}', '${tile.x}').replaceAll('{y}', '${tile.y}');
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
      for (int i = z; i >= 0; i--) {
        final x1 = (x * math.pow(2, i - z)).toInt();
        final y1 = (y * math.pow(2, i - z)).toInt();
        final key1 = (x1 << 32) + y1;
        final tile1 = tiles[i][key1];
        if (tile1?.status == TileStatus.ready) return tile1;
      }
    }
    return tile;
  }

  List<Offset> clipTiles(Rect clipRect, double radius) {
    final list = List<Offset>();
    final scale = math.pow(2.0, zoomLevel);
    if (zoomLevel <= 2) {
      for (double y = 0; y < scale; y++) {
        for (double x = 0; x < scale; x++) {
          list.add(Offset(x, y));
        }
      }
      return list;
    }

    final observed = HashMap<int, int>();
    final lastKeys = List<int>(clipRect.width ~/ 10 + 1);
    for (var y = clipRect.top; y < clipRect.bottom; y += 10.0) {
      var i = 0;
      for (var x = clipRect.left; x < clipRect.right; x += 10.0) {
        final v = canvasPointToVector3(Offset(x, y));
        final latLon = canvasVector3ToLatLon(v);
        final point = latLonToPoint(latLon.latitude, latLon.longitude) * scale;
        final key = (point.dx.toInt() << 32) + point.dy.toInt();
        if ((i == 0 || lastKeys[i - 1] != key) && (lastKeys[i] != key) && !observed.containsKey(key)) {
          observed[key] = 0;
          list.add(Offset(point.dx.truncateToDouble(), point.dy.truncateToDouble()));
        }
        lastKeys[i] = key;
        i++;
      }
    }
    return list;
  }

  Mesh buildTileMesh(Offset offset, double tileWidth, double tileHeight, int subdivisions, double mapWidth, double mapHeight, double radius) {
    final positions = List<Vector3>();
    final textureCoordinates = List<Offset>();
    final triangleIndices = List<Triangle>();
    var sumOfZ = 0.0;
    //Rotate the tile from initial LatLon(-90, -90) to LatLon(0, 0) first.
    final q = Quaternion(-0.5, -0.5, 0.5, 0.5) * quaternion;
    //Use matrix rotation is more efficient.
    final matrix = q.asRotationMatrix()..invert();

    for (var j = 0; j <= subdivisions; j++) {
      final y0 = (offset.dy + tileHeight * j / subdivisions) / mapHeight;
      for (var i = 0; i <= subdivisions; i++) {
        final x0 = (offset.dx + tileWidth * i / subdivisions) / mapWidth;
        final latLon = pointToLatLon(x0, y0);
        final v = latLonToVector3(latLon)..scale(radius);
        v.applyMatrix3(matrix);
        // q.rotate(v);
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

  void drawTiles(Canvas canvas, Size size) {
    final tiles = clipTiles(Rect.fromLTWH(0, 0, width, height), radius);
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
  }

  void _handleScaleStart(ScaleStartDetails details) {
    animController.stop();
    _lastZoom = null;
    _lastFocalPoint = details.localFocalPoint;
    _lastQuaternion = quaternion;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.scale != 1.0 || details.rotation != 0.0) {
      _lastGestureScale = details.scale;
      _lastGestureRatation = details.rotation;
      _lastGestureTime = DateTime.now().millisecondsSinceEpoch;
    }

    if (_lastZoom == null) {
      // fixed scaling error caused by ScaleUpdate delay
      _lastZoom = zoom - math.log(details.scale) / math.ln2;
    } else {
      zoom = _lastZoom + math.log(details.scale) / math.ln2;
    }

    final Vector3 oldCoord = canvasPointToVector3(_lastFocalPoint);
    final Vector3 newCoord = canvasPointToVector3(details.localFocalPoint);
    //var q = Quaternion.fromTwoVectors(newCoord, oldCoord); // It seems some issues with this 'fromTwoVectors' function.
    Quaternion q = quaternionFromTwoVectors(newCoord, oldCoord);
    // final axis = q.axis; // It seems some issues with this 'axis' function.
    final axis = quaternionAxis(q);
    if (axis.x != 0 && axis.y != 0 && axis.z != 0) _lastRotationAxis = axis;

    q *= Quaternion.axisAngle(Vector3(0, 0, 1.0), -details.rotation);
    quaternion = _lastQuaternion * q; //quaternion A * B is not equal to B * A

    if (widget.onCameraMove != null) {
      widget.onCameraMove(position, zoom);
    }
    setState(() {});
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _lastQuaternion = quaternion;
    const double duration = 1000;
    const double maxDistance = 4000;
    final double distance = math.min(maxDistance, details.velocity.pixelsPerSecond.distance) / maxDistance;
    if (distance == 0) return;

    if (DateTime.now().millisecondsSinceEpoch - _lastGestureTime < 300) {
      if (_lastGestureScale != 1.0 && (_lastGestureScale - 1.0).abs() > _lastGestureRatation.abs()) {
        double radians = 1.5 * distance;
        if (_lastGestureScale < 1.0) radians = -radians;
        animController.duration = Duration(milliseconds: duration.toInt());
        zoomAnimation = Tween<double>(begin: zoom, end: zoom + radians).animate(CurveTween(curve: Curves.decelerate).animate(animController));
        panAnimation = null;
        riseAnimation = null;
        animController.reset();
        animController.forward();
        return;
      } else if (_lastGestureRatation != 0) {
        double radians = math.pi * distance;
        if (_lastGestureRatation > 0) radians = -radians;
        _lastRotationAxis = Vector3(0, 0, 1.0);
        animController.duration = Duration(milliseconds: duration.toInt());
        panAnimation = Tween<double>(begin: 0, end: radians).animate(CurveTween(curve: Curves.decelerate).animate(animController));
        riseAnimation = null;
        zoomAnimation = null;
        animController.reset();
        animController.forward();
        return;
      }
    }

    double radians = 1000 * distance / radius;
    final Offset center = Offset(width / 2, height / 2);
    final Vector3 oldCoord = canvasPointToVector3(center);
    final Vector3 newCoord = canvasPointToVector3(center + details.velocity.pixelsPerSecond / distance);
    Quaternion q = quaternionFromTwoVectors(newCoord, oldCoord);
    final Vector3 axis = quaternionAxis(q);
    if (axis.x != 0 && axis.y != 0 && axis.z != 0) _lastRotationAxis = axis;

    animController.duration = Duration(milliseconds: duration.toInt());
    panAnimation = Tween<double>(begin: 0, end: radians).animate(CurveTween(curve: Curves.decelerate).animate(animController));
    riseAnimation = null;
    zoomAnimation = null;
    animController.reset();
    animController.forward();
  }

  void _handleDoubleTap() {
    _lastZoom = zoom;
    animController.duration = Duration(milliseconds: 600);
    zoomAnimation = Tween<double>(begin: zoom, end: zoom + 1.0).animate(CurveTween(curve: Curves.decelerate).animate(animController));
    panAnimation = null;
    riseAnimation = null;
    animController.reset();
    animController.forward();
  }

  void animateCamera({LatLon newLatLon, double riseZoom, double fallZoom, double panSpeed = 1000.0, double riseSpeed = 1.0, double fallSpeed = 1.0}) {
    double panTime = 0;
    double riseTime = 0;
    double fallTime = 0;
    if (riseZoom != null) riseTime = Duration.millisecondsPerSecond * (riseZoom - zoom).abs() / riseSpeed;
    riseZoom ??= zoom;
    if (fallZoom != null) fallTime = Duration.millisecondsPerSecond * (fallZoom - riseZoom).abs() / fallSpeed;
    fallZoom ??= riseZoom;

    double panRadians;
    if (newLatLon != null) {
      final oldEuler = quaternionToEulerAngles(quaternion);
      final newEuler = latLonToEulerAngles(newLatLon);
      //Prevent the rotation over 180 degrees.
      if ((oldEuler.yaw - newEuler.yaw).abs() > math.pi) {
        newEuler.yaw -= math.pi * 2.0;
      }
      // q2 = q0 * q1 then q1 = q0.inverted * q2, and q0 = q2 * q1.inverted
      final q0 = eulerAnglesToQuaternion(oldEuler);
      final q2 = eulerAnglesToQuaternion(newEuler);
      final q1 = q0.inverted() * q2;
      _lastRotationAxis = quaternionAxis(q1); //q1.axis;
      _lastQuaternion = q0;
      panRadians = q1.radians;
      panTime = Duration.millisecondsPerSecond * (panRadians * _radius * math.pow(2, riseZoom)).abs() / panSpeed;
    }

    int duration = (riseTime + panTime + fallTime).ceil();
    animController.duration = Duration(milliseconds: duration);
    final double riseCurveEnd = riseTime / duration;
    riseAnimation = Tween<double>(begin: zoom, end: riseZoom).animate(
      CurveTween(curve: Interval(0, riseCurveEnd, curve: Curves.ease)).animate(animController),
    );
    final double panCurveEnd = riseCurveEnd + panTime / duration;
    _panCurveEnd = panCurveEnd;
    panAnimation = Tween<double>(begin: 0, end: panRadians).animate(
      CurveTween(curve: Interval(riseCurveEnd, panCurveEnd, curve: Curves.ease)).animate(animController),
    );
    final double fallCurveEnd = 1.0;
    zoomAnimation = Tween<double>(begin: riseZoom, end: fallZoom).animate(
      CurveTween(curve: Interval(panCurveEnd, fallCurveEnd, curve: Curves.ease)).animate(animController),
    );
    animController.reset();
    animController.forward();
  }

  @override
  void initState() {
    super.initState();
    tiles = List(maxZoom + 1);
    for (var i = 0; i <= maxZoom; i++) tiles[i] = HashMap<int, Tile>();

    zoom = math.log(widget.radius / _radius) / math.ln2;

    animController = AnimationController(vsync: this)
      ..addListener(() {
        setState(() {
          if (!animController.isCompleted) {
            if (panAnimation != null) {
              final q = Quaternion.axisAngle(_lastRotationAxis, panAnimation.value);
              quaternion = _lastQuaternion * q;
            }
            if (riseAnimation != null) {
              if (animController.value < _panCurveEnd) zoom = riseAnimation.value;
            }
            if (zoomAnimation != null) {
              if (animController.value >= _panCurveEnd) zoom = zoomAnimation.value;
            }
            if (widget.onCameraMove != null) widget.onCameraMove(position, zoom);
          } else {
            _panCurveEnd = 0;
          }
        });
      });

    _controller = FlutterEarthController(this);
    if (widget.onMapCreated != null) {
      widget.onMapCreated(_controller);
    }
  }

  @override
  void dispose() {
    animController.dispose();
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
          child: CustomPaint(
            painter: SpherePainter(this),
            size: Size(constraints.maxWidth, constraints.maxHeight),
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
    canvas.translate(size.width / 2, size.height / 2);
    state.drawTiles(canvas, size);
  }

  // We should repaint whenever the board changes, such as board.selected.
  @override
  bool shouldRepaint(SpherePainter oldDelegate) {
    return true;
  }
}

class FlutterEarthController {
  FlutterEarthController(this._state);

  final _FlutterEarthState _state;

  Quaternion get quaternion => _state.quaternion;
  EulerAngles get eulerAngles => _state.eulerAngles;
  LatLon get position => _state.position;
  double get zoom => _state.zoom;
  bool get isAnimating => _state.animController.isAnimating;

  void animateCamera({LatLon newLatLon, double riseZoom, double fallZoom, double panSpeed = 10.0, double riseSpeed = 1.0, double fallSpeed = 1.0}) {
    _state.animateCamera(newLatLon: newLatLon, riseZoom: riseZoom, fallZoom: fallZoom, panSpeed: panSpeed, riseSpeed: riseSpeed, fallSpeed: fallSpeed);
  }
}
