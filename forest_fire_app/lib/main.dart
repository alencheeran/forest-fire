import 'dart:ui';
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';

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

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  LatLng? selectedLocation;
  String? selectedLocationName;
  double? fireRadiusMeters;

  final MapController mapController = MapController();
  
  final TextEditingController _tempController = TextEditingController();
  final TextEditingController _rhController = TextEditingController();
  final TextEditingController _windController = TextEditingController();
  final TextEditingController _rainController = TextEditingController();

  Timer? _debounce;
  Iterable<Map<String, dynamic>> _lastOptions = [];
  
  List<Map<String, dynamic>> savedLocations = [];
  List<FlSpot> tempHistorySpots = [];
  List<FlSpot> rhHistorySpots = [];

  bool _showNasaHeatmap = false;
  double _currentElevation = 0.0;
  final String _nasaMapKey = '561c93934c9267b53e6443cf8f06ffcd'; 

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _loadSavedLocations();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    final latTween = Tween<double>(begin: mapController.camera.center.latitude, end: destLocation.latitude);
    final lngTween = Tween<double>(begin: mapController.camera.center.longitude, end: destLocation.longitude);
    final zoomTween = Tween<double>(begin: mapController.camera.zoom, end: destZoom);

    final controller = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this);
    final Animation<double> animation = CurvedAnimation(parent: controller, curve: Curves.fastOutSlowIn);

    controller.addListener(() {
      mapController.move(LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)), zoomTween.evaluate(animation));
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });

    controller.forward();
  }

  Future<void> _loadSavedLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedData = prefs.getString('saved_locations');
    if (savedData != null) {
      setState(() {
        savedLocations = List<Map<String, dynamic>>.from(jsonDecode(savedData));
      });
    }
  }

  Future<void> _saveCurrentLocation() async {
    if (selectedLocation == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    final name = selectedLocationName ?? "Lat: ${selectedLocation!.latitude.toStringAsFixed(2)}, Lon: ${selectedLocation!.longitude.toStringAsFixed(2)}";
    
    final newLoc = {'name': name, 'lat': selectedLocation!.latitude, 'lon': selectedLocation!.longitude};
    setState(() {
      savedLocations.add(newLoc);
    });
    await prefs.setString('saved_locations', jsonEncode(savedLocations));
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Saved $name to Favorites!'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _deleteLocation(int index) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      savedLocations.removeAt(index);
    });
    await prefs.setString('saved_locations', jsonEncode(savedLocations));
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      fireRadiusMeters = null;
      selectedLocationName = "Custom Pin";
    });
    _fetchRealTimeWeather(point);
    _animatedMapMove(point, 12.0);
  }

  Future<void> _fetchRealTimeWeather(LatLng point) async {
    setState(() {
      selectedLocation = point;
    });

    _showGlassLoadingDialog('Fetching live & historical weather...');

    try {
      final url = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=${point.latitude}&longitude=${point.longitude}&current=temperature_2m,relative_humidity_2m,precipitation,wind_speed_10m&hourly=temperature_2m,relative_humidity_2m&past_days=7');
      final response = await http.get(url);

      Navigator.pop(context);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final current = data['current'];

        _currentElevation = (data['elevation'] ?? 0.0).toDouble();

        final temp = current['temperature_2m'] ?? 0.0;
        final rh = current['relative_humidity_2m'] ?? 0.0;
        final wind = current['wind_speed_10m'] ?? 0.0;
        final rain = current['precipitation'] ?? 0.0;

        _tempController.text = temp.toString();
        _rhController.text = rh.toString();
        _windController.text = wind.toString();
        _rainController.text = rain.toString();

        tempHistorySpots.clear();
        rhHistorySpots.clear();
        
        if (data.containsKey('hourly')) {
          final hourly = data['hourly'];
          final List<dynamic> temps = hourly['temperature_2m'];
          final List<dynamic> hums = hourly['relative_humidity_2m'];
          
          for (int i = 0; i < 7; i++) {
            int index = i * 24 + 12; 
            if (index < temps.length && temps[index] != null && hums[index] != null) {
              tempHistorySpots.add(FlSpot(i.toDouble(), (temps[index] as num).toDouble()));
              rhHistorySpots.add(FlSpot(i.toDouble(), (hums[index] as num).toDouble()));
            }
          }
        }

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
    _animatedMapMove(mapController.camera.center, currentZoom + 1);
  }

  void _zoomOut() {
    final currentZoom = mapController.camera.zoom;
    _animatedMapMove(mapController.camera.center, currentZoom - 1);
  }

  Future<Iterable<Map<String, dynamic>>> _getSuggestions(String query) async {
    if (query.isEmpty || query.length < 3) return const Iterable<Map<String, dynamic>>.empty();

    final completer = Completer<Iterable<Map<String, dynamic>>>();
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=5&addressdetails=1');
        final response = await http.get(url, headers: {'User-Agent': 'forest_fire_app/1.0'});

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
      selectedLocationName = selection['display_name'].split(',')[0];
      fireRadiusMeters = null;
    });
    
    _animatedMapMove(newLocation, 12.0);
    _fetchRealTimeWeather(newLocation);
  }

  void _showGlassLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black45,
      builder: (context) => Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.all(30),
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
                  Text(message, style: const TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ),
            ),
          ).animate().fadeIn().scale(),
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
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFFF5722), width: 1.5)),
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.85,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 20,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A24).withOpacity(0.85),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
                border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30, spreadRadius: 5)],
              ),
              child: DefaultTabController(
                length: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 60,
                        height: 6,
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.4), borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            selectedLocationName ?? 'Custom Location',
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ).animate().fadeIn(duration: 500.ms).slideX(begin: -0.1),
                        ),
                        IconButton(
                          icon: const Icon(Icons.star_border, color: Colors.amber, size: 32),
                          onPressed: _saveCurrentLocation,
                          tooltip: "Save to Favorites",
                        ).animate().scale(delay: 300.ms, duration: 400.ms),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const TabBar(
                      indicatorColor: Color(0xFFFF5722),
                      indicatorWeight: 3,
                      labelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      unselectedLabelStyle: TextStyle(fontSize: 16),
                      tabs: [
                        Tab(text: "Live Data"),
                        Tab(text: "7-Day Trends"),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: TabBarView(
                        children: [
                          SingleChildScrollView(
                            child: Column(
                              children: [
                                const SizedBox(height: 10),
                                _buildPremiumTextField('Temperature (°C)', Icons.thermostat, _tempController).animate().fade(delay: 100.ms).slideY(),
                                _buildPremiumTextField('Relative Humidity (%)', Icons.water_drop, _rhController).animate().fade(delay: 200.ms).slideY(),
                                _buildPremiumTextField('Wind Speed (km/h)', Icons.air, _windController).animate().fade(delay: 300.ms).slideY(),
                                _buildPremiumTextField('Rain (mm)', Icons.umbrella, _rainController).animate().fade(delay: 400.ms).slideY(),
                                
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text("Elevation: ${_currentElevation.toStringAsFixed(1)}m", style: TextStyle(color: Colors.white70, fontSize: 14)),
                                ).animate().fade(delay: 500.ms),
                                const SizedBox(height: 20),

                                Container(
                                  width: double.infinity,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFFFF5722), Color(0xFFD84315)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [BoxShadow(color: const Color(0xFFFF5722).withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 5))],
                                  ),
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    ),
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _fetchPrediction();
                                    },
                                    child: const Text('Analyze Risk Level', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                                  ),
                                ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(duration: 2.seconds, color: Colors.white30),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: tempHistorySpots.isEmpty ? const Center(child: Text("No historical data available.")) : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(width: 15, height: 15, decoration: BoxDecoration(color: Colors.orangeAccent, borderRadius: BorderRadius.circular(4))),
                                    const SizedBox(width: 8),
                                    const Text("Temp (°C)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    const SizedBox(width: 24),
                                    Container(width: 15, height: 15, decoration: BoxDecoration(color: Colors.lightBlueAccent, borderRadius: BorderRadius.circular(4))),
                                    const SizedBox(width: 8),
                                    const Text("Humidity (%)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ],
                                ).animate().fade(),
                                const SizedBox(height: 30),
                                Expanded(
                                  child: LineChart(
                                    LineChartData(
                                      gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1)),
                                      titlesData: const FlTitlesData(show: false),
                                      borderData: FlBorderData(show: false),
                                      lineBarsData: [
                                        LineChartBarData(
                                          spots: tempHistorySpots,
                                          isCurved: true,
                                          color: Colors.orangeAccent,
                                          barWidth: 5,
                                          isStrokeCapRound: true,
                                          dotData: const FlDotData(show: false),
                                          belowBarData: BarAreaData(show: true, color: Colors.orangeAccent.withOpacity(0.15)),
                                        ),
                                        LineChartBarData(
                                          spots: rhHistorySpots,
                                          isCurved: true,
                                          color: Colors.lightBlueAccent,
                                          barWidth: 5,
                                          isStrokeCapRound: true,
                                          dotData: const FlDotData(show: false),
                                          belowBarData: BarAreaData(show: true, color: Colors.lightBlueAccent.withOpacity(0.15)),
                                        ),
                                      ],
                                    ),
                                  ).animate().fadeIn(duration: 800.ms).scaleXY(begin: 0.9, end: 1.0, curve: Curves.easeOutBack),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ).animate().slideY(begin: 1.0, end: 0.0, curve: Curves.easeOutExpo, duration: 600.ms);
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
          'elevation': _currentElevation,
        })
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
    Color riskColor = Colors.greenAccent;
    IconData riskIcon = Icons.check_circle;
    
    if (risk == 'Medium') { riskColor = Colors.orangeAccent; riskIcon = Icons.warning; } 
    else if (risk == 'High') { riskColor = Colors.redAccent; riskIcon = Icons.local_fire_department; }

    double expectedAreaHectares = 0.0;
    try { expectedAreaHectares = double.parse(data['expected_area'].replaceAll(RegExp(r'[^0-9.]'), '')); } catch (_) {}
    final double radiusMeters = expectedAreaHectares > 0 ? sqrt((expectedAreaHectares * 10000) / pi) : 0.0;

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) {
        return Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: 340,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E28).withOpacity(0.85), 
                  borderRadius: BorderRadius.circular(30), 
                  border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
                  boxShadow: [BoxShadow(color: riskColor.withOpacity(0.2), blurRadius: 40, spreadRadius: 10)]
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(riskIcon, color: riskColor, size: 70).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(end: 1.1, duration: 1.seconds),
                    const SizedBox(height: 20),
                    Text('${data['fire_probability']} Risk', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)).animate().fadeIn().slideY(),
                    const SizedBox(height: 30),
                    _buildResultRow('Risk Level', data['risk_level'], riskColor).animate().fadeIn(delay: 200.ms),
                    const SizedBox(height: 16),
                    _buildResultRow('Expected Area', data['expected_area'], Colors.white).animate().fadeIn(delay: 300.ms),
                    const SizedBox(height: 40),
                    if (expectedAreaHectares > 0)
                      Container(
                        width: double.infinity,
                        height: 55,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), color: Colors.redAccent.withOpacity(0.2), border: Border.all(color: Colors.redAccent.withOpacity(0.5))),
                        child: TextButton.icon(
                          icon: const Icon(Icons.map, color: Colors.redAccent),
                          label: const Text('Visualize Spread', style: TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() { fireRadiusMeters = radiusMeters; });
                            if (selectedLocation != null) _animatedMapMove(selectedLocation!, 13.0);
                          },
                        ),
                      ).animate().scale(delay: 500.ms, curve: Curves.easeOutBack),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: TextButton(
                        style: TextButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Dismiss', style: TextStyle(color: Colors.white, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ).animate().fadeIn(duration: 300.ms).scaleXY(begin: 0.8, end: 1.0, curve: Curves.easeOutBack),
        );
      },
    );
  }

  Widget _buildResultRow(String label, String value, Color valueColor) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 18)), Text(value, style: TextStyle(color: valueColor, fontSize: 18, fontWeight: FontWeight.bold))]);
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
                decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.redAccent.withOpacity(0.5))),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 48).animate().shake(hz: 4, duration: 500.ms),
                    const SizedBox(height: 16),
                    Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 24),
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK', style: TextStyle(color: Colors.redAccent))),
                  ],
                ),
              ),
            ).animate().fadeIn().scale(),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      drawer: Drawer(
        backgroundColor: const Color(0xFF1A1A24).withOpacity(0.95),
        child: Column(
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.transparent),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star, color: Colors.amber, size: 50),
                    SizedBox(height: 10),
                    Text('Saved Locations', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            if (savedLocations.isEmpty)
              const Expanded(child: Center(child: Text("No saved locations yet.", style: TextStyle(color: Colors.white54)))),
            if (savedLocations.isNotEmpty)
              Expanded(
                child: ListView.separated(
                  itemCount: savedLocations.length,
                  separatorBuilder: (context, index) => Divider(color: Colors.white.withOpacity(0.1)),
                  itemBuilder: (context, index) {
                    final loc = savedLocations[index];
                    return ListTile(
                      leading: const Icon(Icons.location_on, color: Color(0xFFFF5722)),
                      title: Text(loc['name'], style: const TextStyle(color: Colors.white, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.white54), onPressed: () => _deleteLocation(index)),
                      onTap: () {
                        Navigator.pop(context);
                        final pt = LatLng(loc['lat'], loc['lon']);
                        setState(() { selectedLocationName = loc['name']; fireRadiusMeters = null; });
                        _animatedMapMove(pt, 12.0);
                        _fetchRealTimeWeather(pt);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      appBar: AppBar(
        title: const Text('DeepFire Predictor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.black.withOpacity(0.4)),
          ),
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(initialCenter: const LatLng(41.8333, -6.8333), initialZoom: 10.0, onTap: _onMapTap),
            children: [
              TileLayer(urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png', subdomains: const ['a', 'b', 'c'], userAgentPackageName: 'com.example.forest_fire_app'),
              
              if (_showNasaHeatmap)
                TileLayer(
                  wmsOptions: WMSTileLayerOptions(
                    baseUrl: 'https://firms.modaps.eosdis.nasa.gov/mapserver/wms/fires/latest/$_nasaMapKey/?',
                    layers: const ['fires_viirs_7'], 
                    format: 'image/png',
                    transparent: true,
                  ),
                ),

              if (selectedLocation != null && fireRadiusMeters != null) 
                CircleLayer(circles: [CircleMarker(point: selectedLocation!, color: Colors.redAccent.withOpacity(0.3), borderColor: Colors.redAccent, borderStrokeWidth: 2, useRadiusInMeter: true, radius: fireRadiusMeters!)]),
              
              if (selectedLocation != null) 
                MarkerLayer(markers: [
                  Marker(
                    point: selectedLocation!, 
                    width: 80, height: 80, 
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.8, end: 1.2).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut)),
                      child: const Icon(Icons.location_on, color: Color(0xFFFF5722), size: 60, shadows: [Shadow(color: Colors.black, blurRadius: 15, offset: Offset(0, 8))]),
                    ),
                  )
                ]),
            ],
          ).animate().fadeIn(duration: 1.seconds),
          
          Positioned(
            top: 110, left: 20, right: 20,
            child: Autocomplete<Map<String, dynamic>>(
              optionsBuilder: (textEditingValue) => _getSuggestions(textEditingValue.text),
              displayStringForOption: (option) => option['display_name'],
              onSelected: _onSuggestionSelected,
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: MediaQuery.of(context).size.width - 40, margin: const EdgeInsets.only(top: 10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: Container(
                            decoration: BoxDecoration(color: const Color(0xFF1E1E28).withOpacity(0.95), border: Border.all(color: Colors.white.withOpacity(0.1)), borderRadius: BorderRadius.circular(20)),
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8), shrinkWrap: true, itemCount: options.length,
                              separatorBuilder: (context, index) => Divider(color: Colors.white.withOpacity(0.1)),
                              itemBuilder: (context, index) {
                                final option = options.elementAt(index);
                                return ListTile(
                                  leading: const Icon(Icons.location_city, color: Color(0xFFFF5722)),
                                  title: Text(option['display_name'], style: const TextStyle(color: Colors.white, fontSize: 16), maxLines: 2, overflow: TextOverflow.ellipsis),
                                  onTap: () => onSelected(option),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ).animate().fadeIn().slideY(begin: -0.1),
                );
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white.withOpacity(0.2)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)]),
                      child: Row(
                        children: [
                          Icon(Icons.search, color: Colors.white.withOpacity(0.8), size: 28),
                          const SizedBox(width: 15),
                          Expanded(child: TextField(controller: controller, focusNode: focusNode, style: const TextStyle(color: Colors.white, fontSize: 18), decoration: InputDecoration(hintText: 'Search for a location...', hintStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 18), border: InputBorder.none))),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ).animate().slideY(begin: -1.5, duration: 800.ms, curve: Curves.easeOutExpo).fadeIn(),
          ),

          Positioned(
            bottom: 160, right: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: _showNasaHeatmap ? Colors.redAccent.withOpacity(0.9) : Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
                    boxShadow: [if (_showNasaHeatmap) BoxShadow(color: Colors.redAccent.withOpacity(0.4), blurRadius: 20, spreadRadius: 2)]
                  ),
                  child: IconButton(
                    iconSize: 28, color: Colors.white, tooltip: 'Toggle NASA Live Heatmap',
                    icon: const Icon(Icons.satellite_alt),
                    onPressed: () {
                      setState(() { _showNasaHeatmap = !_showNasaHeatmap; });
                    },
                  ),
                ),
              ),
            ).animate().slideX(begin: 1.5, delay: 300.ms, duration: 600.ms, curve: Curves.easeOutBack),
          ),

          Positioned(
            bottom: 40, right: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5)),
                  child: Column(
                    children: [
                      IconButton(onPressed: _zoomIn, icon: const Icon(Icons.add, color: Colors.white, size: 30)),
                      Container(height: 1.5, width: 35, color: Colors.white.withOpacity(0.2)),
                      IconButton(onPressed: _zoomOut, icon: const Icon(Icons.remove, color: Colors.white, size: 30)),
                    ],
                  ),
                ),
              ),
            ).animate().slideX(begin: 1.5, delay: 400.ms, duration: 600.ms, curve: Curves.easeOutBack),
          ),
        ],
      ),
    );
  }
}
