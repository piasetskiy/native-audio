import 'package:flutter/material.dart';
import 'package:native_audio/native_audio.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _audio = NativeAudio.build();
  var _isLoaded = false;
  var _isPlaying = false;
  var _status = "stopped";

  @override
  void initState() {
    super.initState();
    _listenForAudioEvents();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Native Audio'),
          ),
          body: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(_status, textAlign: TextAlign.center),
              ),
              if (!_isLoaded)
                MaterialButton(
                  child: Text("Play"),
                  onPressed: () => _playSampleAudio(),
                ),
              if (_isLoaded)
                MaterialButton(
                  child: Text("Stop"),
                  onPressed: () => _audio.stop(),
                ),
              if (!_isPlaying && _isLoaded)
                MaterialButton(
                  child: Text("Resume"),
                  onPressed: () => _audio.resume(),
                ),
              if (_isPlaying && _isLoaded)
                MaterialButton(
                  child: Text("Pause"),
                  onPressed: () => _audio.pause(),
                ),
            ],
          ),
        ),
      );

  void _listenForAudioEvents() {
    _audio.didLoad = (audioDuration) {
      setState(() {
        _isLoaded = true;
        _isPlaying = true;
        _status = "loaded";
      });
    };

    _audio.didResume = () {
      setState(() => _isPlaying = true);
      _status = "resumed";
    };

    _audio.didPause = () {
      setState(() {
        _isPlaying = false;
        _status = "paused";
      });
    };

    _audio.didStop = () {
      setState(() {
        _isLoaded = false;
        _isPlaying = false;
        _status = "stopped";
      });
    };

    _audio.didComplete = () {
      setState(() {
        _isLoaded = false;
        _isPlaying = false;
        _status = "completed";
      });
    };
  }

  void _playSampleAudio() {
    _audio.play(
      "https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3",
      title: "How The Fashion Industry Is Responding To Climate Change",
      album: "Science Friday",
      artist: "WNYC Studio",
      imageUrl:
          "https://www.sciencefriday.com/wp-content/uploads/2019/09/clothes-close-min.jpg",
    );
  }
}
