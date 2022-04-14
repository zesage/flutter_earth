library flutter_earth;

import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter/services.dart' show rootBundle;
import 'package:vector_math/vector_math_64.dart' hide Colors;

/// load an image from asset
Future<Image> loadImageFromAsset(String fileName) {
  final c = Completer<Image>();
  rootBundle.load(fileName).then((data) {
    instantiateImageCodec(data.buffer.asUint8List()).then((codec) {
      codec.getNextFrame().then((frameInfo) {
        c.complete(frameInfo.image);
      });
    });
  }).catchError((error) {
    c.completeError(error);
  });
  return c.future;
}

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
  final latitude =
      2.0 * math.atan(math.exp(math.pi - 2.0 * math.pi * y)) - math.pi / 2.0;
  return LatLon(latitude, longitude);
}

/// Cartesian coordinate conversions
Vector3 latLonToVector3(LatLon latLon) {
  final cosLat = math.cos(latLon.latitude);
  final x = cosLat * math.cos(latLon.longitude);
  final y = cosLat * math.sin(latLon.longitude);
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
  return new Vector3(
      _qStorage[0] * scale, _qStorage[1] * scale, _qStorage[2] * scale);
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

  EulerAngles inRadians() =>
      EulerAngles(radians(yaw), radians(pitch), radians(roll));
  EulerAngles inDegrees() =>
      EulerAngles(degrees(yaw), degrees(pitch), degrees(roll));
  @override
  String toString() =>
      'pitch:${pitch.toStringAsFixed(4)}, yaw:${yaw.toStringAsFixed(4)}, roll:${roll.toStringAsFixed(4)}';
}

class LatLon {
  LatLon(this.latitude, this.longitude);
  double latitude;
  double longitude;
  LatLon inRadians() => LatLon(radians(latitude), radians(longitude));
  LatLon inDegrees() => LatLon(degrees(latitude), degrees(longitude));
  @override
  String toString() =>
      'LatLon(${degrees(latitude).toStringAsFixed(2)}, ${degrees(longitude).toStringAsFixed(2)})';
}

class Polygon {
  Polygon(this.vertex0, this.vertex1, this.vertex2, [this.sumOfZ = 0]);
  int vertex0;
  int vertex1;
  int vertex2;
  double sumOfZ;
}

class Mesh {
  Mesh(int vertexCount, int faceCount) {
    positions = Float32List(vertexCount * 2);
    positionsZ = Float32List(vertexCount);
    texcoords = Float32List(vertexCount * 2);
    colors = Int32List(vertexCount);
    indices = Uint16List(faceCount * 3);
    this.vertexCount = 0;
    this.indexCount = 0;
  }
  late Float32List positions;
  late Float32List positionsZ;
  late Float32List texcoords;
  late Int32List colors;
  late Uint16List indices;
  late int vertexCount;
  late int indexCount;
  Image? texture;
  double x = 0;
  double y = 0;
  double z = 0;
}

enum TileStatus {
  clear,
  pending,
  fetching,
  ready,
  error,
}

class Tile {
  Tile(this.x, this.y, this.z,
      {this.image, this.future, required this.imageProvider});
  int x;
  int y;

  /// zoom level
  int z;
  TileStatus status = TileStatus.clear;
  Image? image;
  Future<Image>? future;
  ImageProvider imageProvider;
  ImageStream? _imageStream;
  ImageStreamListener? _listener;

  void _tileOnLoad(
      ImageInfo imageInfo, bool synchronousCall, Completer<Image> completer) {
    completer.complete(imageInfo.image);
  }

  Future<void> loadImage() async {
    status = TileStatus.fetching;
    final c = Completer<Image>();
    final oldImageStream = _imageStream;
    _imageStream = imageProvider.resolve(const ImageConfiguration());
    if (_imageStream!.key != oldImageStream?.key) {
      if (_listener != null) oldImageStream?.removeListener(_listener!);

      _listener = ImageStreamListener((info, s) => _tileOnLoad(info, s, c),
          onError: (exception, stackTrace) {
        c.completeError(exception, stackTrace);
      });
      _imageStream!.addListener(_listener!);
      try {
        image = await c.future;
        status = TileStatus.ready;
      } catch (e) {
        status = TileStatus.error;
      }
    }
  }
}

typedef TileCallback = void Function(Tile tile);
typedef void MapCreatedCallback(FlutterEarthController controller);
typedef void CameraPositionCallback(LatLon latLon, double zoom);

class FlutterEarth extends StatefulWidget {
  FlutterEarth(
      {Key? key,
      required this.url,
      this.radius,
      this.maxVertexCount = 5000,
      this.showPole = true,
      this.onMapCreated,
      this.onCameraMove,
      this.onTileStart,
      this.onTileEnd,
      this.imageProvider})
      : super(key: key);
  final String url;
  final double? radius;
  final int maxVertexCount;
  final bool? showPole;
  final TileCallback? onTileStart;
  final TileCallback? onTileEnd;
  final MapCreatedCallback? onMapCreated;
  final CameraPositionCallback? onCameraMove;
  final ImageProvider Function(String url)? imageProvider;

  @override
  _FlutterEarthState createState() => _FlutterEarthState();
}

class _FlutterEarthState extends State<FlutterEarth>
    with TickerProviderStateMixin {
  late final FlutterEarthController _controller;
  double width = 0;
  double height = 0;
  double zoom = 0;
  double? _lastZoom = 0;
  Offset _lastFocalPoint = Offset(0, 0);
  Quaternion? _lastQuaternion;
  Vector3 _lastRotationAxis = Vector3(0, 0, 0);
  double _lastGestureScale = 1;
  double _lastGestureRatation = 0;
  int _lastGestureTime = 0;

  final double _radius = 256 / (2 * math.pi);
  double get radius => _radius * math.pow(2, zoom);
  int get zoomLevel => zoom.round().clamp(minZoom, maxZoom);
  LatLon get position => quaternionToLatLon(quaternion);
  EulerAngles get eulerAngles => quaternionToEulerAngles(quaternion);

  Quaternion quaternion = Quaternion.identity();
  late AnimationController animController;
  Animation<double>? panAnimation;
  Animation<double>? riseAnimation;
  Animation<double>? zoomAnimation;
  double _panCurveEnd = 0;

  final double tileWidth = 256;
  final double tileHeight = 256;
  final int minZoom = 2;
  final int maxZoom = 21;
  List<HashMap<int, Tile>> tiles = [];
  Image? northPoleImage;
  Image? southPoleImage;

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

  void clearCache() async {
    final int currentZoom = zoomLevel;
    for (int z = 4; z < tiles.length; z++) {
      if (z != currentZoom) {
        final values = tiles[z].values;
        for (Tile t in values) {
          t.status = TileStatus.clear;
          t.image = null;
          t.future = null;
        }
      }
    }
  }

  Future<Tile> loadTileImage(Tile tile) async {
    if (tile.status == TileStatus.error) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    tile.status = TileStatus.pending;
    if (widget.onTileStart != null) widget.onTileStart!(tile);
    if (tile.status == TileStatus.ready) return tile;
    await tile.loadImage();
    if (widget.onTileEnd != null) widget.onTileEnd!(tile);
    if (mounted) setState(() {});

    return tile;
  }

  Tile? getTile(int x, int y, int z) {
    final key = (x << 32) + y;
    var tile = tiles[z][key];
    if (tile == null) {
      final url = widget.url
          .replaceAll('{z}', '$z')
          .replaceAll('{x}', '$x')
          .replaceAll('{y}', '$y');
      tile = Tile(x, y, z,
          imageProvider: widget.imageProvider != null
              ? widget.imageProvider!(url)
              : NetworkImage(url));
      tiles[z][key] = tile;
    }
    if (tile.status == TileStatus.clear || tile.status == TileStatus.error) {
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
    final list = <Offset>[];
    final scale = math.pow(2.0, zoomLevel).toDouble();
    final observed = HashMap<int, int>();
    final lastKeys = List.filled(clipRect.width ~/ 10 + 1, 0);
    for (var y = clipRect.top; y < clipRect.bottom; y += 10.0) {
      var i = 0;
      for (var x = clipRect.left; x < clipRect.right; x += 10.0) {
        final v = canvasPointToVector3(Offset(x, y));
        final latLon = canvasVector3ToLatLon(v);
        final point = latLonToPoint(latLon.latitude, latLon.longitude) * scale;
        if (point.dx >= scale || point.dy >= scale) continue;
        final key = (point.dx.toInt() << 32) + point.dy.toInt();
        if ((i == 0 || lastKeys[i - 1] != key) &&
            (lastKeys[i] != key) &&
            !observed.containsKey(key)) {
          observed[key] = 0;
          list.add(
              Offset(point.dx.truncateToDouble(), point.dy.truncateToDouble()));
        }
        lastKeys[i] = key;
        i++;
      }
    }
    return list;
  }

  void initMeshTexture(Mesh mesh) {
    final tile = getTile(mesh.x ~/ tileWidth, mesh.y ~/ tileHeight, zoomLevel);
    if (tile?.status == TileStatus.ready) {
      //Is zoomed tile?
      if (tile?.z != zoomLevel && tile != null) {
        final Float32List texcoords = mesh.texcoords;
        final int texcoordCount = texcoords.length;
        final double scale = math.pow(2, tile.z - zoomLevel).toDouble();
        for (int i = 0; i < texcoordCount; i += 2) {
          texcoords[i] = (mesh.x + texcoords[i]) * scale - tile.x * tileWidth;
          texcoords[i + 1] =
              (mesh.y + texcoords[i + 1]) * scale - tile.y * tileHeight;
        }
      }
      mesh.texture = tile?.image;
    }
  }

  Mesh initMeshFaces(Mesh mesh, int subdivisionsX, int subdivisionsY) {
    final int faceCount = subdivisionsX * subdivisionsY * 2;
    final List<Polygon?> _faces = <Polygon?>[]..length = (faceCount);
    final Float32List positionsZ = mesh.positionsZ;
    int indexOffset = mesh.indexCount;
    double z = 0.0;
    for (var j = 0; j < subdivisionsY; j++) {
      int k1 = j * (subdivisionsX + 1);
      int k2 = k1 + subdivisionsX + 1;
      for (var i = 0; i < subdivisionsX; i++) {
        int k3 = k1 + 1;
        int k4 = k2 + 1;
        double sumOfZ = positionsZ[k1] + positionsZ[k2] + positionsZ[k3];
        _faces[indexOffset] = Polygon(k1, k2, k3, sumOfZ);
        z += sumOfZ;
        sumOfZ = positionsZ[k3] + positionsZ[k2] + positionsZ[k4];
        _faces[indexOffset + 1] = Polygon(k3, k2, k4, sumOfZ);
        z += sumOfZ;
        indexOffset += 2;
        k1++;
        k2++;
      }
    }
    mesh.indexCount += faceCount;

    var faces = _faces.whereType<Polygon>().toList();

    faces.sort((Polygon a, Polygon b) {
      // return b.sumOfZ.compareTo(a.sumOfZ);
      final double az = a.sumOfZ;
      final double bz = b.sumOfZ;
      if (bz > az) return 1;
      if (bz < az) return -1;
      return 0;
    });

    // convert Polygon list to Uint16List
    final int indexCount = faces.length;
    final Uint16List indices = mesh.indices;
    for (int i = 0; i < indexCount; i++) {
      final int index0 = i * 3;
      final int index1 = index0 + 1;
      final int index2 = index0 + 2;
      final Polygon polygon = faces[i];
      indices[index0] = polygon.vertex0;
      indices[index1] = polygon.vertex1;
      indices[index2] = polygon.vertex2;
    }

    mesh.z = z;
    return mesh;
  }

  Mesh buildPoleMesh(double startLatitude, double endLatitude, int subdivisions,
      Image? image) {
    //Rotate the tile from initial LatLon(-90, -90) to LatLon(0, 0) first.
    final q = Quaternion(-0.5, -0.5, 0.5, 0.5) * quaternion;
    //Use matrix rotation is more efficient.
    final matrix = q.asRotationMatrix()..invert();

    final int imageWidth = image?.width ?? 1;
    final int imageHeight = image?.height ?? 1;
    final int subdivisionsX = subdivisions * (imageWidth ~/ imageHeight);
    final int vertexCount = (subdivisions + 1) * (subdivisionsX + 1);
    final int faceCount = subdivisions * subdivisionsX * 2;
    final Mesh mesh = Mesh(vertexCount, faceCount);
    final Float32List texcoords = mesh.texcoords;
    final Float32List positions = mesh.positions;
    final Float32List positionsZ = mesh.positionsZ;
    int vertexIndex = 0;
    int vertexZIndex = 0;
    int texcoordIndex = 0;

    final double stepOfLat = (endLatitude - startLatitude) / subdivisions;
    final double stepOfLon = 2 * math.pi / subdivisionsX;
    for (int j = 0; j <= subdivisions; j++) {
      final double y0 = startLatitude + stepOfLat * j;
      for (int i = 0; i <= subdivisionsX; i++) {
        final double x0 = -math.pi + i * stepOfLon;
        final v = latLonToVector3(LatLon(y0, x0))..scale(radius);
        v.applyMatrix3(matrix);
        // q.rotate(v);
        final Float64List storage4 = v.storage;
        positions[vertexIndex] = storage4[0]; //v.x;
        positions[vertexIndex + 1] = storage4[1]; //v.y;
        positionsZ[vertexZIndex] = storage4[2]; //v.z;
        vertexIndex += 2;
        vertexZIndex++;

        texcoords[texcoordIndex] = imageWidth * i / subdivisionsX;
        texcoords[texcoordIndex + 1] = imageHeight * j / subdivisions;
        texcoordIndex += 2;
      }
    }
    mesh.vertexCount += vertexCount;
    mesh.x = -1;
    mesh.y = -1;
    mesh.texture = image;
    return initMeshFaces(mesh, subdivisionsX, subdivisions);
  }

  Mesh buildTileMesh(
      double offsetX,
      double offsetY,
      double tileWidth,
      double tileHeight,
      int subdivisions,
      double mapWidth,
      double mapHeight,
      double radius) {
    //Rotate the tile from initial LatLon(-90, -90) to LatLon(0, 0) first.
    final q = Quaternion(-0.5, -0.5, 0.5, 0.5) * quaternion;
    //Use matrix rotation is more efficient.
    final matrix = q.asRotationMatrix()..invert();

    final int vertexCount = (subdivisions + 1) * (subdivisions + 1);
    final int faceCount = subdivisions * subdivisions * 2;
    final Mesh mesh = Mesh(vertexCount, faceCount);
    final Float32List texcoords = mesh.texcoords;
    final Float32List positions = mesh.positions;
    final Float32List positionsZ = mesh.positionsZ;
    int vertexIndex = 0;
    int vertexZIndex = 0;
    int texcoordIndex = 0;

    for (var j = 0; j <= subdivisions; j++) {
      final y0 = (offsetY + tileHeight * j / subdivisions) / mapHeight;
      for (var i = 0; i <= subdivisions; i++) {
        final x0 = (offsetX + tileWidth * i / subdivisions) / mapWidth;
        final latLon = pointToLatLon(x0, y0);
        final v = latLonToVector3(latLon)..scale(radius);
        v.applyMatrix3(matrix);
        // q.rotate(v);
        final Float64List storage4 = v.storage;
        positions[vertexIndex] = storage4[0]; //v.x;
        positions[vertexIndex + 1] = storage4[1]; //v.y;
        positionsZ[vertexZIndex] = storage4[2]; //v.z;
        vertexIndex += 2;
        vertexZIndex++;

        texcoords[texcoordIndex] = tileWidth * i / subdivisions;
        texcoords[texcoordIndex + 1] = tileHeight * j / subdivisions;
        texcoordIndex += 2;
      }
    }
    mesh.vertexCount += vertexCount;
    mesh.x = offsetX;
    mesh.y = offsetY;
    return initMeshFaces(mesh, subdivisions, subdivisions);
  }

  void drawTiles(Canvas canvas, Size size) {
    final tiles = clipTiles(Rect.fromLTWH(0, 0, width, height), radius);
    final meshList = <Mesh>[];
    final maxWidth = tileWidth * (1 << zoomLevel);
    final maxHeight = tileHeight * (1 << zoomLevel);

    final tileCount = math.pow(math.pow(2, zoomLevel), 2);
    final int subdivisions =
        math.max(2, math.sqrt(widget.maxVertexCount / tileCount).toInt());
    for (var t in tiles) {
      final mesh = buildTileMesh(
        t.dx * tileWidth,
        t.dy * tileHeight,
        tileWidth,
        tileHeight,
        subdivisions,
        maxWidth,
        maxHeight,
        radius,
      );
      initMeshTexture(mesh);
      meshList.add(mesh);
    }
    if (widget.showPole ?? false) {
      meshList..add(buildPoleMesh(math.pi / 2, radians(84), 5, northPoleImage));
      meshList
          .add(buildPoleMesh(-radians(84), -math.pi / 2, 5, southPoleImage));
    }

    meshList.sort((Mesh a, Mesh b) {
      return b.z.compareTo(a.z);
    });

    for (var mesh in meshList) {
      final vertices = Vertices.raw(
        VertexMode.triangles,
        mesh.positions,
        textureCoordinates: mesh.texcoords,
        indices: mesh.indices,
      );

      final paint = Paint();
      if (mesh.texture != null) {
        Float64List matrix4 = new Matrix4.identity().storage;
        final shader = ImageShader(
            mesh.texture!, TileMode.mirror, TileMode.mirror, matrix4);
        paint.shader = shader;
      }
      canvas.drawVertices(vertices, BlendMode.src, paint);
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
      zoom = _lastZoom! + math.log(details.scale) / math.ln2;
    }

    final Vector3 oldCoord = canvasPointToVector3(_lastFocalPoint);
    final Vector3 newCoord = canvasPointToVector3(details.localFocalPoint);
    //var q = Quaternion.fromTwoVectors(newCoord, oldCoord); // It seems some issues with this 'fromTwoVectors' function.
    Quaternion q = quaternionFromTwoVectors(newCoord, oldCoord);
    // final axis = q.axis; // It seems some issues with this 'axis' function.
    final axis = quaternionAxis(q);
    if (axis.x != 0 && axis.y != 0 && axis.z != 0) _lastRotationAxis = axis;

    q *= Quaternion.axisAngle(Vector3(0, 0, 1.0), -details.rotation);
    if (_lastQuaternion != null)
      quaternion =
          _lastQuaternion! * q; //quaternion A * B is not equal to B * A

    if (widget.onCameraMove != null) {
      widget.onCameraMove!(position, zoom);
    }
    if (mounted) setState(() {});
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _lastQuaternion = quaternion;
    const double duration = 1000;
    const double maxDistance = 4000;
    final double distance =
        math.min(maxDistance, details.velocity.pixelsPerSecond.distance) /
            maxDistance;
    if (distance == 0) return;

    if (DateTime.now().millisecondsSinceEpoch - _lastGestureTime < 300) {
      if (_lastGestureScale != 1.0 &&
          (_lastGestureScale - 1.0).abs() > _lastGestureRatation.abs()) {
        double radians = 3.0 * distance;
        if (_lastGestureScale < 1.0) radians = -radians;
        animController.duration = Duration(milliseconds: duration.toInt());
        zoomAnimation = Tween<double>(begin: zoom, end: zoom + radians).animate(
            CurveTween(curve: Curves.decelerate).animate(animController));
        panAnimation = null;
        riseAnimation = null;
        animController.reset();
        animController.forward();
        return;
      } else if (_lastGestureRatation != 0) {
        double radians = 2.0 * math.pi * distance;
        if (_lastGestureRatation > 0) radians = -radians;
        _lastRotationAxis = Vector3(0, 0, 1.0);
        animController.duration = Duration(milliseconds: duration.toInt());
        panAnimation = Tween<double>(begin: 0, end: radians).animate(
            CurveTween(curve: Curves.decelerate).animate(animController));
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
    final Vector3 newCoord = canvasPointToVector3(
        center + details.velocity.pixelsPerSecond / distance);
    Quaternion q = quaternionFromTwoVectors(newCoord, oldCoord);
    final Vector3 axis = quaternionAxis(q);
    if (axis.x != 0 && axis.y != 0 && axis.z != 0) _lastRotationAxis = axis;

    animController.duration = Duration(milliseconds: duration.toInt());
    panAnimation = Tween<double>(begin: 0, end: radians)
        .animate(CurveTween(curve: Curves.decelerate).animate(animController));
    riseAnimation = null;
    zoomAnimation = null;
    animController.reset();
    animController.forward();
  }

  void _handleDoubleTap() {
    _lastZoom = zoom;
    animController.duration = Duration(milliseconds: 600);
    zoomAnimation = Tween<double>(begin: zoom, end: zoom + 1.0)
        .animate(CurveTween(curve: Curves.decelerate).animate(animController));
    panAnimation = null;
    riseAnimation = null;
    animController.reset();
    animController.forward();
  }

  void animateCamera(
      {LatLon? newLatLon,
      double? riseZoom,
      double? fallZoom,
      double panSpeed = 1000.0,
      double riseSpeed = 1.0,
      double fallSpeed = 1.0}) {
    double panTime = 0;
    double riseTime = 0;
    double fallTime = 0;
    if (riseZoom != null)
      riseTime =
          Duration.millisecondsPerSecond * (riseZoom - zoom).abs() / riseSpeed;
    riseZoom ??= zoom;
    if (fallZoom != null)
      fallTime = Duration.millisecondsPerSecond *
          (fallZoom - riseZoom).abs() /
          fallSpeed;
    fallZoom ??= riseZoom;

    double panRadians = 0;
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
      panTime = Duration.millisecondsPerSecond *
          (panRadians * _radius * math.pow(2, riseZoom)).abs() /
          panSpeed;
    }

    int duration = (riseTime + panTime + fallTime).ceil();
    animController.duration = Duration(milliseconds: duration);
    final double riseCurveEnd = riseTime / duration;
    riseAnimation = Tween<double>(begin: zoom, end: riseZoom).animate(
      CurveTween(curve: Interval(0, riseCurveEnd, curve: Curves.ease))
          .animate(animController),
    );
    final double panCurveEnd = riseCurveEnd + panTime / duration;
    _panCurveEnd = panCurveEnd;
    panAnimation = Tween<double>(begin: 0, end: panRadians).animate(
      CurveTween(curve: Interval(riseCurveEnd, panCurveEnd, curve: Curves.ease))
          .animate(animController),
    );
    const double fallCurveEnd = 1.0;
    zoomAnimation = Tween<double>(begin: riseZoom, end: fallZoom).animate(
      CurveTween(curve: Interval(panCurveEnd, fallCurveEnd, curve: Curves.ease))
          .animate(animController),
    );
    animController.reset();
    animController.forward();
  }

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance!.imageCache!.maximumSizeBytes = 1024 * 1024 * 520;
    var _tiles = <HashMap<int, Tile>?>[]..length = (maxZoom + 1);
    for (var i = 0; i <= maxZoom; i++) {
      _tiles[i] = HashMap<int, Tile>();
    }
    tiles = _tiles.whereType<HashMap<int, Tile>>().toList();
    if (widget.radius != null) {
      zoom = math.log(widget.radius! / _radius) / math.ln2;
    }
    _lastRotationAxis = Vector3(0, 0, 1.0);

    animController = AnimationController(vsync: this)
      ..addListener(() {
        if (mounted)
          setState(() {
            if (!animController.isCompleted) {
              if (panAnimation != null && _lastQuaternion != null) {
                final q = Quaternion.axisAngle(
                    _lastRotationAxis, panAnimation!.value);
                quaternion = _lastQuaternion! * q;
              }
              if (riseAnimation != null) {
                if (animController.value < _panCurveEnd)
                  zoom = riseAnimation!.value;
              }
              if (zoomAnimation != null) {
                if (animController.value >= _panCurveEnd)
                  zoom = zoomAnimation!.value;
              }
              if (widget.onCameraMove != null)
                widget.onCameraMove!(position, zoom);
            } else {
              _panCurveEnd = 0;
            }
          });
      });

    _controller = FlutterEarthController(this);
    if (widget.onMapCreated != null) {
      widget.onMapCreated!(_controller);
    }

    loadImageFromAsset(
            'packages/flutter_earth/assets/google_map_north_pole.png')
        .then((Image value) => northPoleImage = value);
    loadImageFromAsset(
            'packages/flutter_earth/assets/google_map_south_pole.png')
        .then((Image value) => southPoleImage = value);
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

  void clearCache() => _state.clearCache();

  void animateCamera(
      {LatLon? newLatLon,
      double? riseZoom,
      double? fallZoom,
      double panSpeed = 10.0,
      double riseSpeed = 1.0,
      double fallSpeed = 1.0}) {
    _state.animateCamera(
        newLatLon: newLatLon,
        riseZoom: riseZoom,
        fallZoom: fallZoom,
        panSpeed: panSpeed,
        riseSpeed: riseSpeed,
        fallSpeed: fallSpeed);
  }
}
