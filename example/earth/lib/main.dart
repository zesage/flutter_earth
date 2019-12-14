import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_earth/flutter_earth.dart';
import 'package:flutter/services.dart' show rootBundle;

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Earth Demo',
      theme: ThemeData.dark(),
      home: MyHomePage(title: 'Flutter Earth'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  FlutterEarthController _controller;
  double _zoom = 0;
  LatLon _position = LatLon(0, 0);
  String _cityName = '';
  dynamic _cityList;
  int _subdivisions = 9;

  void _incrementCounter() {
    setState(() {
      _subdivisions++;
    });
  }

  void _onMapCreated(FlutterEarthController controller) {
    _controller = controller;
    _moveToNextCity();
  }

  void _onCameraMove(LatLon latLon, double zoom) {
    setState(() {
      _zoom = zoom;
      _position = latLon.inDegrees();
    });
  }

  void _moveToNextCity() {
    if (!_controller.isAnimating && _cityList != null) {
      final int index = Random().nextInt(_cityList.length);
      final dynamic city = _cityList[index];
      final double lat = double.parse(city['latitude']);
      final double lon = double.parse(city['longitude']);
      _cityName = city['city'];
      _controller.animateCamera(newLatLon: LatLon(lat, lon).inRadians(), riseZoom: 3.0, fallZoom: 11.0, panSpeed: 500, riseSpeed: 3, fallSpeed: 2);
    }
  }

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/city.json').then((String data) {
      _cityList = json.decode(data);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                Expanded(
                  child: FlutterEarth(
                    url: 'http://mt0.google.cn/vt/lyrs=y&hl=en&x={x}&y={y}&z={z}',
                    radius: 160,
                    subdivisions: _subdivisions % 10 + 1,
                    onMapCreated: _onMapCreated,
                    onCameraMove: _onCameraMove,
                  ),
                ),
              ],
            ),
            Column(
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      'lat:${_position.latitude.toStringAsFixed(2)} lon:${_position.longitude.toStringAsFixed(2)} zoom:${_zoom.toStringAsFixed(2)}',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                Text(_cityName),
                IconButton(
                    icon: Icon(Icons.location_searching),
                    onPressed: () {
                      _moveToNextCity();
                    }),
              ],
            )
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
