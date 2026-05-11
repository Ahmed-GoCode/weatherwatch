import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const WeatherWatchApp());
}

// ─── App ──────────────────────────────────────────────────────────────────────

class WeatherWatchApp extends StatelessWidget {
  const WeatherWatchApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WeatherWatch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF64B5F6),
          surface: Color(0xFF0D1B2A),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// ─── Constants ────────────────────────────────────────────────────────────────

class K {
  static const apiKey = String.fromEnvironment(
    'OPENWEATHER_API_KEY',
    defaultValue: 'YOUR_OPENWEATHER_API_KEY',
  );
  static const base    = 'https://api.openweathermap.org/data/2.5';
  static const geo     = 'https://api.openweathermap.org/geo/1.0';
  static const icons   = 'https://openweathermap.org/img/wn';
  static const kCity   = 'city';
  static const kMetric = 'metric';
}

// ─── Models ───────────────────────────────────────────────────────────────────

class Weather {
  final String city, country, condition, description, icon;
  final double temp, feelsLike, tempMin, tempMax, windSpeed;
  final int humidity, pressure, visibility, sunrise, sunset, windDeg;
  final DateTime fetchedAt;

  Weather({
    required this.city, required this.country,
    required this.condition, required this.description, required this.icon,
    required this.temp, required this.feelsLike,
    required this.tempMin, required this.tempMax,
    required this.windSpeed, required this.windDeg,
    required this.humidity, required this.pressure, required this.visibility,
    required this.sunrise, required this.sunset,
    required this.fetchedAt,
  });

  factory Weather.fromJson(Map<String, dynamic> j) => Weather(
    city:        j['name'],
    country:     j['sys']['country'],
    condition:   j['weather'][0]['main'],
    description: j['weather'][0]['description'],
    icon:        j['weather'][0]['icon'],
    temp:        (j['main']['temp']       as num).toDouble(),
    feelsLike:   (j['main']['feels_like'] as num).toDouble(),
    tempMin:     (j['main']['temp_min']   as num).toDouble(),
    tempMax:     (j['main']['temp_max']   as num).toDouble(),
    windSpeed:   (j['wind']['speed']      as num).toDouble(),
    windDeg:     (j['wind']['deg']        as num? ?? 0).toInt(),
    humidity:    j['main']['humidity'],
    pressure:    j['main']['pressure'],
    visibility:  j['visibility'] ?? 10000,
    sunrise:     j['sys']['sunrise'],
    sunset:      j['sys']['sunset'],
    fetchedAt:   DateTime.now(),
  );
}

class Hourly {
  final DateTime time;
  final double temp;
  final String icon;
  final int pop;

  Hourly({required this.time, required this.temp,
          required this.icon, required this.pop});

  factory Hourly.fromJson(Map<String, dynamic> j) => Hourly(
    time: DateTime.fromMillisecondsSinceEpoch(j['dt'] * 1000),
    temp: (j['main']['temp'] as num).toDouble(),
    icon: j['weather'][0]['icon'],
    pop:  ((j['pop'] as num? ?? 0) * 100).round(),
  );
}

class Daily {
  final DateTime date;
  final double tempMin, tempMax;
  final String icon, description;
  final int pop;

  Daily({required this.date, required this.tempMin, required this.tempMax,
         required this.icon, required this.description, required this.pop});
}

class Suggestion {
  final String name, country;
  final String? state;
  final double lat, lon;

  Suggestion({required this.name, required this.country,
              this.state, required this.lat, required this.lon});

  factory Suggestion.fromJson(Map<String, dynamic> j) => Suggestion(
    name:    j['name'],
    country: j['country'],
    state:   j['state'],
    lat:     (j['lat'] as num).toDouble(),
    lon:     (j['lon'] as num).toDouble(),
  );

  String get label => state != null ? '$name, $state, $country' : '$name, $country';
}

// ─── API Service ──────────────────────────────────────────────────────────────

class Api {
  final String units;
  Api(bool metric) : units = metric ? 'metric' : 'imperial';

  Future<Map<String, dynamic>> _get(String url) async {
    final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (r.statusCode == 200)  return jsonDecode(r.body);
    if (r.statusCode == 401)  throw 'Invalid API key.';
    if (r.statusCode == 404)  throw 'City not found.';
    if (r.statusCode == 429)  throw 'Rate limit reached. Wait a moment.';
    throw 'Server error ${r.statusCode}.';
  }

  String _w(Map<String, String> p) {
    final q = {'appid': K.apiKey, 'units': units, ...p};
    return '${K.base}/weather?${_enc(q)}';
  }

  String _f(Map<String, String> p) {
    final q = {'appid': K.apiKey, 'units': units, ...p};
    return '${K.base}/forecast?${_enc(q)}';
  }

  String _enc(Map<String, String> p) =>
      p.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');

  Future<Weather> weatherByCity(String city) async =>
      Weather.fromJson(await _get(_w({'q': city})));

  Future<Weather> weatherByCoords(double lat, double lon) async =>
      Weather.fromJson(await _get(_w({'lat': '$lat', 'lon': '$lon'})));

  Future<List<Hourly>> hourly(String city) async {
    final d = await _get(_f({'q': city, 'cnt': '8'}));
    return (d['list'] as List).map((e) => Hourly.fromJson(e)).toList();
  }

  Future<List<Daily>> forecast(String city) async {
    final d = await _get(_f({'q': city, 'cnt': '40'}));
    final Map<String, List> grouped = {};
    for (final item in d['list'] as List) {
      final dt  = DateTime.fromMillisecondsSinceEpoch(item['dt'] * 1000);
      final key = '${dt.year}-${dt.month}-${dt.day}';
      grouped.putIfAbsent(key, () => []).add(item);
    }
    final today = DateTime.now();
    return grouped.entries.where((e) {
      final p = e.key.split('-');
      final dt = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      return !(dt.day == today.day && dt.month == today.month);
    }).take(7).map((e) {
      final readings = e.value;
      final noon = readings.firstWhere(
        (r) { final h = DateTime.fromMillisecondsSinceEpoch(r['dt']*1000).hour;
               return h >= 11 && h <= 14; },
        orElse: () => readings.last,
      );
      final temps = readings.map<double>((r) => (r['main']['temp'] as num).toDouble()).toList();
      return Daily(
        date:        DateTime.fromMillisecondsSinceEpoch(readings.first['dt'] * 1000),
        tempMin:     temps.reduce((a, b) => a < b ? a : b),
        tempMax:     temps.reduce((a, b) => a > b ? a : b),
        icon:        noon['weather'][0]['icon'],
        description: noon['weather'][0]['description'],
        pop:         ((noon['pop'] as num? ?? 0) * 100).round(),
      );
    }).toList();
  }

  Future<List<Suggestion>> suggest(String q) async {
    if (q.length < 2) return [];
    final url = '${K.geo}/direct?q=${Uri.encodeComponent(q)}&limit=5&appid=${K.apiKey}';
    final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return [];
    return (jsonDecode(r.body) as List).map((e) => Suggestion.fromJson(e)).toList();
  }
}

// ─── Splash ───────────────────────────────────────────────────────────────────

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashState();
}

class _SplashState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1000))..forward();
  late final _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
        transitionDuration: const Duration(milliseconds: 600),
      ));
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF0D1B2A), Color(0xFF1B3A5C), Color(0xFF0A1628)],
      )),
      child: Center(
        child: FadeTransition(opacity: _fade, child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 96, height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                boxShadow: [BoxShadow(
                  color: const Color(0xFF64B5F6).withOpacity(0.45),
                  blurRadius: 32, spreadRadius: 6,
                )],
              ),
              child: const Icon(Icons.wb_sunny_rounded, size: 48, color: Colors.white),
            ),
            const SizedBox(height: 22),
            const Text('WeatherWatch', style: TextStyle(
              fontSize: 34, fontWeight: FontWeight.w700,
              color: Colors.white, letterSpacing: 1.5,
            )),
            const SizedBox(height: 8),
            Text('Your world. Your weather.', style: TextStyle(
              fontSize: 14, color: Colors.white.withOpacity(0.5), letterSpacing: 1,
            )),
          ],
        )),
      ),
    ),
  );
}

// ─── Home ─────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeState();
}

class _HomeState extends State<HomeScreen> with TickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  final _focus      = FocusNode();

  bool     _metric    = true;
  bool     _loading   = false;
  bool     _searching = false;
  String?  _error;

  Weather?          _weather;
  List<Hourly>      _hourly      = [];
  List<Daily>       _daily       = [];
  List<Suggestion>  _suggestions = [];

  late final _fadeCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500));
  late final _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);

  Api get _api => Api(_metric);

  @override
  void initState() { super.initState(); _boot(); }

  @override
  void dispose() {
    _searchCtrl.dispose(); _focus.dispose(); _fadeCtrl.dispose(); super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────────

  Future<void> _boot() async {
    final p = await SharedPreferences.getInstance();
    _metric = p.getBool(K.kMetric) ?? true;
    await _load(p.getString(K.kCity) ?? 'London');
  }

  Future<void> _load(String city) async {
    setState(() { _loading = true; _error = null; _searching = false; _suggestions = []; });
    _fadeCtrl.reset();
    try {
      final w = await _api.weatherByCity(city);
      final h = await _api.hourly(city);
      final d = await _api.forecast(city);
      final p = await SharedPreferences.getInstance();
      await p.setString(K.kCity, city);
      if (!mounted) return;
      setState(() { _weather = w; _hourly = h; _daily = d; _loading = false; });
      _fadeCtrl.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _gps() async {
    setState(() => _loading = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw 'Location disabled.';
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) throw 'Permission denied.';
      }
      if (perm == LocationPermission.deniedForever) throw 'Permission permanently denied.';
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
      final w   = await _api.weatherByCoords(pos.latitude, pos.longitude);
      await _load(w.city);
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _onType(String q) async {
    if (q.length < 2) { setState(() => _suggestions = []); return; }
    final s = await _api.suggest(q);
    if (mounted) setState(() => _suggestions = s);
  }

  Future<void> _toggleUnit() async {
    setState(() => _metric = !_metric);
    final p = await SharedPreferences.getInstance();
    await p.setBool(K.kMetric, _metric);
    if (_weather != null) await _load(_weather!.city);
  }

  // ── Theme ──────────────────────────────────────────────────────────────────

  List<Color> get _bg {
    if (_weather == null) return [const Color(0xFF0D1B2A), const Color(0xFF1B3A5C)];
    final c = _weather!.condition.toLowerCase();
    final n = _weather!.icon.endsWith('n');
    if (c.contains('thunder'))                         return [const Color(0xFF120227), const Color(0xFF2D1B69)];
    if (c.contains('snow'))                            return [const Color(0xFF1A2A38), const Color(0xFF37474F)];
    if (c.contains('rain') || c.contains('drizzle'))  return n
        ? [const Color(0xFF0A1520), const Color(0xFF1A3040)]
        : [const Color(0xFF1B3A5C), const Color(0xFF2A4F6E)];
    if (c.contains('cloud'))                           return n
        ? [const Color(0xFF141E30), const Color(0xFF243B55)]
        : [const Color(0xFF2C3E50), const Color(0xFF4A6375)];
    return n
        ? [const Color(0xFF0D1B2A), const Color(0xFF1B2838)]
        : [const Color(0xFF1565C0), const Color(0xFF42A5F5)];
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    body: AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: _bg,
      )),
      child: SafeArea(child: Column(children: [
        _topBar(),
        _searchField(),
        if (_suggestions.isNotEmpty && _searching) _suggestionBox(),
        Expanded(child: _content()),
      ])),
    ),
  );

  // ── Widgets ────────────────────────────────────────────────────────────────

  Widget _topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
    child: Row(children: [
      const Icon(Icons.wb_sunny_rounded, color: Color(0xFF64B5F6), size: 24),
      const SizedBox(width: 8),
      const Text('WeatherWatch', style: TextStyle(
        color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: 0.5,
      )),
      const Spacer(),
      _chip(onTap: _toggleUnit,
        child: Text(_metric ? '°C' : '°F',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))),
      const SizedBox(width: 8),
      _chip(onTap: _gps,
        child: const Icon(Icons.my_location_rounded, color: Colors.white, size: 18)),
    ]),
  );

  Widget _chip({required Widget child, required VoidCallback onTap}) =>
    GestureDetector(onTap: onTap, child: ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: child,
        ),
      ),
    ));

  Widget _searchField() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: TextField(
          controller: _searchCtrl,
          focusNode: _focus,
          onTap: () => setState(() => _searching = true),
          onChanged: (v) { setState(() => _searching = true); _onType(v); },
          onSubmitted: (v) { if (v.trim().isNotEmpty) _load(v.trim()); },
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Search any city in the world…',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.45)),
            prefixIcon: const Icon(Icons.search, color: Colors.white54),
            suffixIcon: _searching && _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() { _searching = false; _suggestions = []; });
                    _focus.unfocus();
                  })
              : null,
            filled: true,
            fillColor: Colors.white.withOpacity(0.12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF64B5F6), width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    ),
  );

  Widget _suggestionBox() => Container(
    margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
    decoration: BoxDecoration(
      color: const Color(0xFF0D1B2A).withOpacity(0.97),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withOpacity(0.1)),
    ),
    child: Column(children: _suggestions.map((s) => ListTile(
      dense: true,
      leading: const Icon(Icons.location_on, color: Color(0xFF64B5F6), size: 18),
      title: Text(s.label, style: const TextStyle(color: Colors.white, fontSize: 13)),
      onTap: () {
        _searchCtrl.text = s.name;
        _focus.unfocus();
        setState(() { _searching = false; _suggestions = []; });
        _load(s.name);
      },
    )).toList()),
  );

  Widget _content() {
    if (_loading) return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      CircularProgressIndicator(color: Color(0xFF64B5F6)),
      SizedBox(height: 14),
      Text('Fetching weather…', style: TextStyle(color: Colors.white54)),
    ]));

    if (_error != null) return Center(child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_rounded, size: 64, color: Colors.white30),
        const SizedBox(height: 16),
        Text(_error!, textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => _load(_weather?.city ?? 'London'),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try Again'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF64B5F6), foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ]),
    ));

    if (_weather == null) return const SizedBox();

    return FadeTransition(
      opacity: _fadeAnim,
      child: RefreshIndicator(
        color: const Color(0xFF64B5F6),
        backgroundColor: const Color(0xFF0D1B2A),
        onRefresh: () => _load(_weather!.city),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 36),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _currentCard(),
            const SizedBox(height: 14),
            _statsRow(),
            const SizedBox(height: 14),
            _sunCard(),
            const SizedBox(height: 14),
            _hourlyCard(),
            const SizedBox(height: 14),
            _forecastCard(),
            const SizedBox(height: 12),
            _footer(),
          ]),
        ),
      ),
    );
  }

  // ── Current card ────────────────────────────────────────────────────────────

  Widget _currentCard() {
    final w = _weather!;
    final u = _metric ? '°C' : '°F';
    return _glass(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.location_on_rounded, color: Color(0xFF64B5F6), size: 16),
        const SizedBox(width: 4),
        Expanded(child: Text('${w.city}, ${w.country}', style: const TextStyle(
          color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
        Text(DateFormat('EEE, d MMM').format(DateTime.now()),
          style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13)),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${w.temp.round()}$u', style: const TextStyle(
            color: Colors.white, fontSize: 76, fontWeight: FontWeight.w200, height: 1)),
          const SizedBox(height: 6),
          Text(w.description.toUpperCase(), style: const TextStyle(
            color: Color(0xFF64B5F6), fontSize: 12, letterSpacing: 2.5,
            fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Feels like ${w.feelsLike.round()}$u',
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
          const SizedBox(height: 2),
          Text('H ${w.tempMax.round()}$u  ·  L ${w.tempMin.round()}$u',
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
        ])),
        Image.network(
          '${K.icons}/${w.icon}@4x.png', width: 110, height: 110,
          errorBuilder: (_, __, ___) =>
            const Icon(Icons.wb_sunny_rounded, size: 90, color: Colors.white24),
        ),
      ]),
    ]));
  }

  // ── Stats row ───────────────────────────────────────────────────────────────

  Widget _statsRow() {
    final w = _weather!;
    return Row(children: [
      Expanded(child: _stat(Icons.water_drop_outlined, '${w.humidity}%', 'Humidity')),
      const SizedBox(width: 10),
      Expanded(child: _stat(Icons.air, '${w.windSpeed.toStringAsFixed(1)}\n${_metric ? 'm/s' : 'mph'}', 'Wind')),
      const SizedBox(width: 10),
      Expanded(child: _stat(Icons.compress_rounded, '${w.pressure}\nhPa', 'Pressure')),
      const SizedBox(width: 10),
      Expanded(child: _stat(Icons.visibility_outlined,
        '${(w.visibility / 1000).toStringAsFixed(1)}\nkm', 'Visibility')),
    ]);
  }

  Widget _stat(IconData icon, String val, String label) =>
    _glass(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      child: Column(children: [
        Icon(icon, color: const Color(0xFF64B5F6), size: 21),
        const SizedBox(height: 7),
        Text(val, textAlign: TextAlign.center, style: const TextStyle(
          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, height: 1.3)),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(
          color: Colors.white.withOpacity(0.5), fontSize: 11)),
      ]),
    );

  // ── Sunrise/Sunset ──────────────────────────────────────────────────────────

  Widget _sunCard() {
    final w    = _weather!;
    final rise = DateTime.fromMillisecondsSinceEpoch(w.sunrise * 1000);
    final set  = DateTime.fromMillisecondsSinceEpoch(w.sunset  * 1000);
    final len  = set.difference(rise);
    final prog = (DateTime.now().difference(rise).inMinutes / len.inMinutes).clamp(0.0, 1.0);

    return _glass(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel('SUNRISE & SUNSET'),
      const SizedBox(height: 14),
      Row(children: [
        _sunPill(Icons.wb_twilight_rounded, DateFormat('h:mm a').format(rise),
          'Sunrise', const Color(0xFFFFCC02)),
        Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(children: [
            ClipRRect(borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: prog, minHeight: 7,
                backgroundColor: Colors.white.withOpacity(0.12),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFFFCC02)),
              )),
            const SizedBox(height: 6),
            Text('${len.inHours}h ${len.inMinutes % 60}m of daylight',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
          ]),
        )),
        _sunPill(Icons.nightlight_round, DateFormat('h:mm a').format(set),
          'Sunset', const Color(0xFF90CAF9)),
      ]),
    ]));
  }

  Widget _sunPill(IconData icon, String time, String label, Color color) =>
    Column(children: [
      Icon(icon, color: color, size: 24),
      const SizedBox(height: 5),
      Text(time, style: const TextStyle(
        color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(
        color: Colors.white.withOpacity(0.5), fontSize: 11)),
    ]);

  // ── Hourly ──────────────────────────────────────────────────────────────────

  Widget _hourlyCard() => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel('HOURLY FORECAST'),
      const SizedBox(height: 10),
      SizedBox(height: 116, child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _hourly.length,
        itemBuilder: (_, i) {
          final h = _hourly[i];
          final u = _metric ? '°' : '°';
          return _glass(
            margin: EdgeInsets.only(right: i < _hourly.length - 1 ? 10 : 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(DateFormat('h a').format(h.time),
                style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12)),
              const SizedBox(height: 2),
              Image.network('${K.icons}/${h.icon}@2x.png', width: 42, height: 42,
                errorBuilder: (_, __, ___) =>
                  const Icon(Icons.wb_sunny, size: 30, color: Colors.white24)),
              Text('${h.temp.round()}$u', style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
              if (h.pop > 0) ...[
                const SizedBox(height: 2),
                Text('${h.pop}%', style: const TextStyle(
                  color: Color(0xFF90CAF9), fontSize: 11)),
              ],
            ]),
          );
        },
      )),
    ],
  );

  // ── 7-day forecast ──────────────────────────────────────────────────────────

  Widget _forecastCard() {
    final u = _metric ? '°C' : '°F';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel('7-DAY FORECAST'),
      const SizedBox(height: 10),
      _glass(padding: EdgeInsets.zero, child: Column(
        children: List.generate(_daily.length, (i) {
          final d = _daily[i];
          return Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(children: [
                SizedBox(width: 56, child: Text(
                  i == 0 ? 'Tomorrow' : DateFormat('EEE').format(d.date),
                  style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w500, fontSize: 13))),
                Image.network('${K.icons}/${d.icon}@2x.png', width: 36, height: 36,
                  errorBuilder: (_, __, ___) =>
                    const Icon(Icons.wb_sunny, size: 24, color: Colors.white24)),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.description, style: TextStyle(
                    color: Colors.white.withOpacity(0.6), fontSize: 12)),
                  if (d.pop > 0)
                    Text('${d.pop}% rain', style: const TextStyle(
                      color: Color(0xFF90CAF9), fontSize: 11)),
                ])),
                Text('${d.tempMin.round()}$u', style: TextStyle(
                  color: Colors.white.withOpacity(0.45), fontSize: 14)),
                const SizedBox(width: 12),
                SizedBox(width: 44, child: Text('${d.tempMax.round()}$u',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.white,
                    fontSize: 14, fontWeight: FontWeight.w600))),
              ]),
            ),
            if (i < _daily.length - 1)
              Divider(height: 1, color: Colors.white.withOpacity(0.07)),
          ]);
        }),
      )),
    ]);
  }

  // ── Footer ──────────────────────────────────────────────────────────────────

  Widget _footer() => Center(child: Text(
    'Updated ${DateFormat('h:mm a').format(_weather!.fetchedAt)}  ·  Pull down to refresh',
    style: TextStyle(color: Colors.white.withOpacity(0.28), fontSize: 11),
  ));

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Widget _glass({required Widget child, EdgeInsets? padding, EdgeInsets? margin}) =>
    ClipRRect(borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          margin: margin,
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.14)),
          ),
          child: child,
        ),
      ),
    );

  Widget _sectionLabel(String t) => Text(t, style: TextStyle(
    color: Colors.white.withOpacity(0.55), fontSize: 11,
    letterSpacing: 2.2, fontWeight: FontWeight.w600,
  ));
}
