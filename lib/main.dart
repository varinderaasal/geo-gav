import 'package:aftermidtermcompass/map.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cube/flutter_cube.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart'; // Import for LatLng
import 'dart:async';
import 'dart:math' as math;
import 'map.dart'; // Import the MapScreen

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Sensor subscriptions
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  StreamSubscription<Position>? _positionSubscription;

  // Sensor values
  List<double> _accelerometerValues = [0.0, 0.0, 0.0];
  List<double> _magnetometerValues = [0.0, 0.0, 0.0];

  double _deviceAzimuth = 0.0;
  double _targetBearing = 0.0;
  double _pointerRotation = 0.0;

  // Target location (example: San Francisco)
  final double targetLatitude = 30.892657744694873;
  final double targetLongitude = 75.87247505760351;

  // Camera setup
  List<CameraDescription> cameras = [];
  CameraController? cameraController;

  // Dropdown menu selections
  String? _selectedDeparture;
  String? _selectedArrival;

  // Predefined locations
  List<String> departureLocations = ['Location A', 'Location B', 'Location C'];
  List<String> arrivalLocations = ['Location D', 'Location E', 'Location F'];

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();

    // Gyroscope subscription
    _gyroscopeSubscription = gyroscopeEventStream(samplingPeriod: SensorInterval.normalInterval).listen((GyroscopeEvent event) {
      _updateRotationFromGyroscope(event);
    });

    // Accelerometer subscription
    _accelerometerSubscription = accelerometerEventStream(samplingPeriod: SensorInterval.normalInterval).listen((AccelerometerEvent event) {
      _accelerometerValues = [event.x, event.y, event.z];
    });

    // Magnetometer subscription
    _magnetometerSubscription = magnetometerEventStream(samplingPeriod: SensorInterval.normalInterval).listen((MagnetometerEvent event) {
      _magnetometerValues = [event.x, event.y, event.z];
      _updatePointerRotation();
    });

    _setupCameraController();
  }

  Future<void> _setupCameraController() async {
    List<CameraDescription> _cameras = await availableCameras();
    if (_cameras.isNotEmpty) {
      setState(() {
        cameras = _cameras;
        cameraController = CameraController(
          _cameras.first,
          ResolutionPreset.high,
        );
      });
      cameraController?.initialize().then((_) {
        setState(() {});
      });
    }
  }

  Future<void> _checkLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return;
    }

    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      _startPositionStream();
    }
  }

  void _startPositionStream() {
    LocationSettings locationSettings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    _positionSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
      double bearing = Geolocator.bearingBetween(position.latitude, position.longitude, targetLatitude, targetLongitude);

      setState(() {
        _targetBearing = bearing;
      });
    });
  }

  // Update rotation from gyroscope
  void _updateRotationFromGyroscope(GyroscopeEvent event) {
    setState(() {
      _deviceAzimuth += event.z * (180 / math.pi); // Convert radians to degrees
      if (_deviceAzimuth < 0) _deviceAzimuth += 360;
      if (_deviceAzimuth >= 360) _deviceAzimuth -= 360;
    });
  }

  // Update pointer rotation
  void _updatePointerRotation() {
    double ax = _accelerometerValues[0];
    double ay = _accelerometerValues[1];
    double az = _accelerometerValues[2];

    double mx = _magnetometerValues[0];
    double my = _magnetometerValues[1];
    double mz = _magnetometerValues[2];

    // Calculate device azimuth from sensors
    double azimuth = _calculateAzimuthFromSensors(ax, ay, az, mx, my, mz);

    setState(() {
      _deviceAzimuth = azimuth; // Correct gyroscope drift with sensor azimuth
      _pointerRotation = _targetBearing - _deviceAzimuth;

      if (_pointerRotation < 0) _pointerRotation += 360;
    });
  }

  // Calculate azimuth from sensors
  double _calculateAzimuthFromSensors(double ax, double ay, double az, double mx, double my, double mz) {
    double normA = math.sqrt(ax * ax + ay * ay + az * az);
    ax /= normA;
    ay /= normA;
    az /= normA;

    double normM = math.sqrt(mx * mx + my * my + mz * mz);
    mx /= normM;
    my /= normM;
    mz /= normM;

    double hx = my * az - mz * ay;
    double hy = mz * ax - mx * az;

    double azimuth = math.atan2(hy, hx) * (180 / math.pi);
    if (azimuth < 0) azimuth += 360;

    return azimuth;
  }

  @override
  void dispose() {
    _gyroscopeSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _magnetometerSubscription?.cancel();
    _positionSubscription?.cancel();
    cameraController?.dispose();
    super.dispose();
  }

  Widget buildUI() {
    if (cameraController == null || !cameraController!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Column(
      children: [
        Expanded(
          flex: 6,
          child: Stack(
            children: [
              ClipRect(
                child: OverflowBox(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                  maxWidth: MediaQuery.of(context).size.width,
                  child: CameraPreview(cameraController!),
                ),
              ),
              Center(
                child: Transform.rotate(
                  angle: _pointerRotation * (math.pi / 180),
                  child: const Icon(
                    Icons.navigation,
                    size: 100,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 4,
          child: Container(
            padding: EdgeInsets.all(16.0),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Select Departure:',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                DropdownButton<String>(
                  value: _selectedDeparture,
                  items: departureLocations.map((String location) {
                    return DropdownMenuItem<String>(
                      value: location,
                      child: Text(location),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedDeparture = newValue;
                    });
                  },
                ),
                SizedBox(height: 20),
                Text(
                  'Select Arrival:',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                DropdownButton<String>(
                  value: _selectedArrival,
                  items: arrivalLocations.map((String location) {
                    return DropdownMenuItem<String>(
                      value: location,
                      child: Text(location),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedArrival = newValue;
                    });
                  },
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    if (_selectedDeparture != null && _selectedArrival != null) {
                      // Define departure and arrival coordinates here
                      LatLng departureCoordinates = LatLng(30.888944724091047, 75.87145081086157); // Replace with your actual coordinates
                      LatLng arrivalCoordinates = LatLng(30.889000, 75.872000); // Replace with your actual coordinates

                      // Navigate to the MapScreen with coordinates
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MapScreen(departure: departureCoordinates, arrival: arrivalCoordinates),
                        ),
                      );
                    }
                  },
                  child: Text('Start Navigation'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Indoor Navigation App',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Indoor Navigation'),
        ),
        body: buildUI(),
      ),
    );
  }
}
