import 'dart:ui';
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const ForestFireApp());
}

class ForestFireApp extends StatelessWidget {
  const ForestFireApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Forest Fire Predictor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: const Color(0xFFFF5722),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  LatLng? selectedLocation;
  double? fireRadiusMeters;

  final MapController mapController = MapController();
  
  final TextEditingController _tempController = TextEditingController();
  final TextEditingController _rhController = TextEditingController();
  final TextEditingController _windController = TextEditingController();
  final TextEditingController _rainController = TextEditingController();

  Timer? _debounce;
  Iterable<Map<String, dynamic>> _lastOptions = [];

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      fireRadiusMeters = null;
    });
    _fetchRealTimeWeather(point);
  }

  Future<void> _fetchRealTimeWeather(LatLng point) async {
    setState(() {
      selectedLocation = point;
    });

    _showGlassLoadingDialog('Fetching live weather...');

    try {
      final url = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=${point.latitude}&longitude=${point.longitude}&current=temperature_2m,relative_humidity_2m,precipitation,wind_speed_10m');
      final response = await http.get(url);

      Navigator.pop(context);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final current = data['current'];

        final temp = current['temperature_2m'] ?? 0.0;
        final rh = current['relative_humidity_2m'] ?? 0.0;
        final wind = current['wind_speed_10m'] ?? 0.0;
        final rain = current['precipitation'] ?? 0.0;

        _tempController.text = temp.toString();
        _rhController.text = rh.toString();
        _windController.text = wind.toString();
        _rainController.text = rain.toString();

        _showPredictionBottomSheet();

      } else {
        _showGlassErrorDialog('Weather API failed: ${response.statusCode}');
      }
    } catch (e) {
      Navigator.pop(context);
      _showGlassErrorDialog('Weather fetch failed. Please check your internet connection.');
    }
  }

  void _zoomIn() {
    final currentZoom = mapController.camera.zoom;
    mapController.move(mapController.camera.center, currentZoom + 1);
  }

  void _zoomOut() {
    final currentZoom = mapController.camera.zoom;
    mapController.move(mapController.camera.center, currentZoom - 1);
  }

  // --- Search Autocomplete Logic --- //
  
  Future<Iterable<Map<String, dynamic>>> _getSuggestions(String query) async {
    if (query.isEmpty || query.length < 3) {
      return const Iterable<Map<String, dynamic>>.empty();
    }

    final completer = Completer<Iterable<Map<String, dynamic>>>();

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=5&addressdetails=1');
        final response = await http.get(url, headers: {
          'User-Agent': 'forest_fire_app/1.0',
        });

        if (response.statusCode == 200) {
          final List data = jsonDecode(response.body);
          final suggestions = data.map((item) => {
            'display_name': item['display_name'],
            'lat': double.parse(item['lat']),
            'lon': double.parse(item['lon']),
          }).toList();
          _lastOptions = suggestions;
          completer.complete(suggestions);
        } else {
          completer.complete(_lastOptions);
        }
      } catch (e) {
        completer.complete(_lastOptions);
      }
    });

    return completer.future;
  }

  void _onSuggestionSelected(Map<String, dynamic> selection) {
    final newLocation = LatLng(selection['lat'], selection['lon']);
    
    setState(() {
      selectedLocation = newLocation;
      fireRadiusMeters = null;
    });
    
    mapController.move(newLocation, 12.0);
    _fetchRealTimeWeather(newLocation);
  }

  // --------------------------------- //

  void _showGlassLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black45,
      builder: (context) => Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Color(0xFFFF5722)),
                  const SizedBox(height: 20),
                  Text(
                    message,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumTextField(String label, IconData icon, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
          prefixIcon: Icon(icon, color: const Color(0xFFFF5722)),
          filled: true,
          fillColor: Colors.black.withOpacity(0.3),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Color(0xFFFF5722), width: 1.5),
          ),
        ),
      ),
    );
  }

  void _showPredictionBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 30,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A24).withOpacity(0.85),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 50,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Live Conditions',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 24),
                    _buildPremiumTextField('Temperature (°C)', Icons.thermostat, _tempController),
                    _buildPremiumTextField('Relative Humidity (%)', Icons.water_drop, _rhController),
                    _buildPremiumTextField('Wind Speed (km/h)', Icons.air, _windController),
                    _buildPremiumTextField('Rain (mm)', Icons.umbrella, _rainController),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      height: 55,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF5722), Color(0xFFD84315)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF5722).withOpacity(0.4),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          )
                        ],
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _fetchPrediction();
                        },
                        child: const Text(
                          'Analyze Risk Level',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _fetchPrediction() async {
    _showGlassLoadingDialog('Analyzing AI models...');

    try {
      final double temp = double.tryParse(_tempController.text) ?? 0.0;
      final double rh = double.tryParse(_rhController.text) ?? 0.0;
      final double wind = double.tryParse(_windController.text) ?? 0.0;
      final double rain = double.tryParse(_rainController.text) ?? 0.0;

      final url = Uri.parse('http://127.0.0.1:5000/predict');
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'temp': temp,
          'RH': rh,
          'wind': wind,
          'rain': rain,
        }),
      );

      Navigator.pop(context);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _showGlassResultDialog(data);
      } else {
        _showGlassErrorDialog('Server error: ${response.statusCode}');
      }
    } catch (e) {
      Navigator.pop(context);
      _showGlassErrorDialog('Failed to connect to the server. Is it running?');
    }
  }

  void _showGlassResultDialog(Map<String, dynamic> data) {
    final String risk = data['risk_level'];
    Color riskColor = Colors.green;
    IconData riskIcon = Icons.check_circle;
    
    if (risk == 'Medium') {
      riskColor = Colors.orange;
      riskIcon = Icons.warning;
    } else if (risk == 'High') {
      riskColor = Colors.redAccent;
      riskIcon = Icons.local_fire_department;
    }

    final String areaString = data['expected_area'];
    double expectedAreaHectares = 0.0;
    try {
      expectedAreaHectares = double.parse(areaString.replaceAll(RegExp(r'[^0-9.]'), ''));
    } catch (_) {}

    final double radiusMeters = expectedAreaHectares > 0 
        ? sqrt((expectedAreaHectares * 10000) / pi) 
        : 0.0;

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) {
        return Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                width: 320,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E28).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(riskIcon, color: riskColor, size: 60),
                    const SizedBox(height: 16),
                    Text(
                      '${data['fire_probability']} Risk',
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                    const SizedBox(height: 24),
                    _buildResultRow('Risk Level', data['risk_level'], riskColor),
                    const SizedBox(height: 12),
                    _buildResultRow('Expected Area', data['expected_area'], Colors.white70),
                    const SizedBox(height: 30),
                    
                    if (expectedAreaHectares > 0)
                      Container(
                        width: double.infinity,
                        height: 50,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.redAccent.withOpacity(0.2),
                          border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                        ),
                        child: TextButton.icon(
                          icon: const Icon(Icons.map, color: Colors.redAccent),
                          label: const Text('Visualize Spread', style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() {
                              fireRadiusMeters = radiusMeters;
                            });
                            if (selectedLocation != null) {
                              mapController.move(selectedLocation!, 13.0);
                            }
                          },
                        ),
                      ),

                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.white.withOpacity(0.1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Dismiss', style: TextStyle(color: Colors.white, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildResultRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16)),
        Text(value, style: TextStyle(color: valueColor, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  void _showGlassErrorDialog(String message) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) {
        return Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                width: 300,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('DeepFire Predictor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              color: Colors.black.withOpacity(0.4),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: const LatLng(41.8333, -6.8333),
              initialZoom: 10.0,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.forest_fire_app',
              ),
              if (selectedLocation != null && fireRadiusMeters != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: selectedLocation!,
                      color: Colors.redAccent.withOpacity(0.3),
                      borderColor: Colors.redAccent,
                      borderStrokeWidth: 2,
                      useRadiusInMeter: true,
                      radius: fireRadiusMeters!,
                    ),
                  ],
                ),
              if (selectedLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: selectedLocation!,
                      width: 60,
                      height: 60,
                      child: const Icon(
                        Icons.location_on,
                        color: Color(0xFFFF5722),
                        size: 50,
                        shadows: [
                          Shadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 5))
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
          
          Positioned(
            top: 100,
            left: 20,
            right: 20,
            child: Autocomplete<Map<String, dynamic>>(
              optionsBuilder: (TextEditingValue textEditingValue) {
                return _getSuggestions(textEditingValue.text);
              },
              displayStringForOption: (option) => option['display_name'],
              onSelected: _onSuggestionSelected,
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: MediaQuery.of(context).size.width - 40,
                      margin: const EdgeInsets.only(top: 10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E28).withOpacity(0.9),
                              border: Border.all(color: Colors.white.withOpacity(0.1)),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shrinkWrap: true,
                              itemCount: options.length,
                              separatorBuilder: (context, index) => Divider(color: Colors.white.withOpacity(0.1)),
                              itemBuilder: (context, index) {
                                final option = options.elementAt(index);
                                return ListTile(
                                  leading: const Icon(Icons.location_city, color: Color(0xFFFF5722)),
                                  title: Text(
                                    option['display_name'],
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () {
                                    onSelected(option);
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, color: Colors.white.withOpacity(0.7)),
                          const SizedBox(width: 15),
                          Expanded(
                            child: TextField(
                              controller: controller,
                              focusNode: focusNode,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Search location...',
                                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          Positioned(
            bottom: 40,
            right: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Column(
                    children: [
                      IconButton(
                        onPressed: _zoomIn,
                        icon: const Icon(Icons.add, color: Colors.white),
                      ),
                      Container(height: 1, width: 30, color: Colors.white.withOpacity(0.1)),
                      IconButton(
                        onPressed: _zoomOut,
                        icon: const Icon(Icons.remove, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
