import 'package:flutter/material.dart';
import 'package:flutter_earth/flutter_earth.dart';

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
  int _subdivisions = 9;

  void _incrementCounter() {
    setState(() {
      _subdivisions++;
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: FlutterEarth(
                url: 'http://mt0.google.cn/vt/lyrs=y&hl=en&x={x}&y={y}&z={z}',
                radius: 160,
                subdivisions: _subdivisions % 10 + 1,
                showAxis: true,
              ),
            ),
            Text(
              'subdivisions: ${_subdivisions % 10 + 1}',
              // style: Theme.of(context).textTheme.display1,
            ),
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
