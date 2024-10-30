import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:collection';
import 'dart:math';

class MapScreen extends StatefulWidget {
  final LatLng departure; // Departure point
  final LatLng arrival;   // Arrival point

  MapScreen({required this.departure, required this.arrival}); // Constructor

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  
  List<List<LatLng>> geoJsonPolylines = []; // List of polylines for each LineString
  LatLng? selectedDestination;
  List<LatLng> shortestPathRoute = [];

  @override
  void initState() {
    super.initState();
    _loadGeoJson();  // Load GeoJSON on initialization
  }

  Future<void> _loadGeoJson() async {
    // Load the GeoJSON file from assets
    final String response = await rootBundle.loadString('assets/map.geojson'); // Ensure this matches the file name
    final data = json.decode(response);

    // Extract coordinates from the GeoJSON file
    for (var feature in data['features']) {
      if (feature['geometry']['type'] == 'LineString') {
        List<LatLng> coordinates = [];
        for (var coord in feature['geometry']['coordinates']) {
          coordinates.add(LatLng(coord[1], coord[0]));  // Add to list (lat, long)
        }
        geoJsonPolylines.add(coordinates);  // Add LineString coordinates to the polyline list
      }
    }
    setState(() {});  // Update state to reflect changes
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Indoor Navigation')),
      body: Stack(
        children: [
          map(),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: ElevatedButton(
              onPressed: () {
                if (selectedDestination != null) {
                  calculateShortestPath(widget.departure, selectedDestination!); // Pass departure and selected destination
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Please select a destination")),
                  );
                }
              },
              child: Text("Calculate Shortest Path"),
            ),
          ),
        ],
      ),
    );
  }

  // FlutterMap widget
  Widget map() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: widget.departure, // Center map at departure point
        initialZoom: 16,
        minZoom: 8,
        maxZoom: 20,
        onTap: _handleTap, // Handle map taps for destination selection
      ),
      children: [
        openStreetMapLayer,
        // PolylineLayer to display all the LineStrings
        PolylineLayer(
          polylines: geoJsonPolylines.map((polyline) {
            return Polyline(
              points: polyline,
              strokeWidth: 4.0,
              color: Colors.blue,
            );
          }).toList(),
        ),
        // Draw shortest path if available
        PolylineLayer(
          polylines: [
            Polyline(
              points: shortestPathRoute,
              strokeWidth: 6.0,
              color: Colors.red,
            ),
          ],
        ),
      ],
    );
  }

  // OpenStreetMap Layer
  TileLayer get openStreetMapLayer => TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'dev.fleaflet.flutter.flutter_map.example',
  );

  // Handle Tap for Selecting Destination
  void _handleTap(TapPosition tapPosition, LatLng latlng) {
    setState(() {
      selectedDestination = latlng;
      shortestPathRoute = []; // Reset path
    });
  }

  // Dijkstra's Algorithm for Shortest Path Calculation
  void calculateShortestPath(LatLng start, LatLng end) {
    // Create a graph based on the LineStrings
    Map<LatLng, List<LatLng>> graph = {};

    // Populate the graph with the vertices (LatLng) and their neighbors
    for (var polyline in geoJsonPolylines) {
      for (int i = 0; i < polyline.length - 1; i++) {
        LatLng from = polyline[i];
        LatLng to = polyline[i + 1];

        // Add edges for both directions
        if (!graph.containsKey(from)) {
          graph[from] = [];
        }
        graph[from]!.add(to);

        if (!graph.containsKey(to)) {
          graph[to] = [];
        }
        graph[to]!.add(from);
      }
    }

    // Dijkstra's algorithm implementation
    Map<LatLng, double> distances = {for (var vertex in graph.keys) vertex: double.infinity};
    distances[start] = 0;

    PriorityQueue<LatLng> priorityQueue = PriorityQueue((a, b) => distances[a]!.compareTo(distances[b]!));
    priorityQueue.add(start);

    Map<LatLng, LatLng?> previous = {};

    while (priorityQueue.isNotEmpty) {
      LatLng current = priorityQueue.removeFirst();

      if (current == end) break;  // Stop if we've reached the end

      for (var neighbor in graph[current] ?? []) {
        double newDist = distances[current]! + _distance(current, neighbor);
        if (newDist < distances[neighbor]!) {
          distances[neighbor] = newDist;
          previous[neighbor] = current;
          priorityQueue.add(neighbor);
        }
      }
    }

    // Reconstruct the shortest path
    List<LatLng> path = [];
    LatLng? step = end;
    while (step != null) {
      path.add(step);
      step = previous[step];
    }

    shortestPathRoute = path.reversed.toList();  // Reverse the path
    setState(() {});  // Update state to reflect the shortest path
  }

  // Calculate the distance between two LatLng points (in meters)
  double _distance(LatLng a, LatLng b) {
    const R = 6371000; // Radius of the Earth in meters
    var lat1 = a.latitude * (3.141592653589793238 / 180);
    var lat2 = b.latitude * (3.141592653589793238 / 180);
    var deltaLat = (b.latitude - a.latitude) * (3.141592653589793238 / 180);
    var deltaLon = (b.longitude - a.longitude) * (3.141592653589793238 / 180);

    var aHav = (sin(deltaLat / 2) * sin(deltaLat / 2)) +
               (cos(lat1) * cos(lat2) *
                sin(deltaLon / 2) * sin(deltaLon / 2));
    var c = 2 * atan2(sqrt(aHav), sqrt(1 - aHav));

    return R * c; // Distance in meters
  }
}
