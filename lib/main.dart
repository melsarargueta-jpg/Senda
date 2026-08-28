import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const SendaApp());
}

class SendaApp extends StatelessWidget {
  const SendaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Senda',
      theme: ThemeData(
        primaryColor: const Color(0xFF800020),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const MapaMedicionScreen(),
    );
  }
}

class MapaMedicionScreen extends StatefulWidget {
  const MapaMedicionScreen({super.key});

  @override
  State<MapaMedicionScreen> createState() => _MapaMedicionScreenState();
}

class _MapaMedicionScreenState extends State<MapaMedicionScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  // Listas de datos y trazos
  final List<LatLng> _puntosRuta = [];
  final List<LatLng> _puntosPoligono = [];
  final List<List<LatLng>> _poligonosGuardados = [];
  final List<Map<String, dynamic>> _puntosGeorreferenciados = [];

  double _distanciaTotalKm = 0.0;
  double _areaHectareas = 0.0;
  double _alturaGpsActual = 1243.0;

  // Modos: 'punto', 'gps', 'linea', 'poligono', 'georreferencia'
  String _modoActivo = 'punto';
  bool _buscandoLugar = false;

  // ==========================================
  // BÚSQUEDA DE LUGARES POR NOMBRE (Nominatim)
  // ==========================================
  Future<void> _buscarLugarPorNombre(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _buscandoLugar = true);

    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=1',
    );

    try {
      final response = await http.get(url, headers: {'User-Agent': 'SendaApp/1.0'});
      if (response.statusCode == 200) {
        final List resultados = json.decode(response.body);
        if (resultados.isNotEmpty) {
          final lat = double.parse(resultados[0]['lat']);
          final lon = double.parse(resultados[0]['lon']);
          final puntoDestino = LatLng(lat, lon);

          _mapController.move(puntoDestino, 15.0);
          setState(() {
            _puntosRuta.add(puntoDestino);
          });
          _mostrarMensaje('Lugar encontrado: ${resultados[0]['display_name']}');
        } else {
          _mostrarMensaje('No se encontró el lugar.');
        }
      }
    } catch (e) {
      _mostrarMensaje('Error en la búsqueda: $e');
    } finally {
      setState(() => _buscandoLugar = false);
    }
  }

  // ==========================================
  // CÁLCULOS DE DISTANCIA Y ÁREA
  // ==========================================
  void _calcularDistancia() {
    if (_puntosRuta.length < 2) {
      setState(() => _distanciaTotalKm = 0.0);
      return;
    }
    double distanciaTotal = 0.0;
    final Distance distance = Distance();
    for (int i = 0; i < _puntosRuta.length - 1; i++) {
      distanciaTotal += distance.as(LengthUnit.Kilometer, _puntosRuta[i], _puntosRuta[i + 1]);
    }
    setState(() => _distanciaTotalKm = distanciaTotal);
  }

  void _calcularArea() {
    if (_puntosPoligono.length < 3) {
      setState(() => _areaHectareas = 0.0);
      return;
    }
    double area = 0.0;
    int n = _puntosPoligono.length;
    const double radioTierra = 6378137.0;

    for (int i = 0; i < n; i++) {
      int j = (i + 1) % n;
      var p1 = _puntosPoligono[i];
      var p2 = _puntosPoligono[j];

      double lat1 = p1.latitude * (math.pi / 180);
      double lat2 = p2.latitude * (math.pi / 180);
      double lon1 = p1.longitude * (math.pi / 180);
      double lon2 = p2.longitude * (math.pi / 180);

      area += (lon2 - lon1) * (2 + math.sin(lat1) + math.sin(lat2));
    }
    area = (area * radioTierra * radioTierra / 2.0).abs();
    setState(() => _areaHectareas = area / 10000.0);
  }

  // ==========================================
  // ACCIÓN AL TOCAR EL MAPA
  // ==========================================
  void _alHacerTapEnMapa(TapPosition tapPosition, LatLng punto) {
    setState(() {
      if (_modoActivo == 'linea' || _modoActivo == 'punto') {
        _puntosRuta.add(punto);
        _calcularDistancia();
      } else if (_modoActivo == 'poligono') {
        _puntosPoligono.add(punto);
        _calcularArea();
      } else if (_modoActivo == 'georreferencia') {
        _puntosGeorreferenciados.add({
          'nombre': 'Punto #${_puntosGeorreferenciados.length + 1}',
          'lat': punto.latitude,
          'lng': punto.longitude,
          'altura': _alturaGpsActual,
        });
        _mostrarMensaje('Punto georreferenciado guardado con éxito');
      }
    });
  }

  void _limpiarTodo() {
    setState(() {
      _puntosRuta.clear();
      _puntosPoligono.clear();
      _puntosGeorreferenciados.clear();
      _distanciaTotalKm = 0.0;
      _areaHectareas = 0.0;
    });
  }

  void _mostrarMensaje(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    const colorRojoVino = Color(0xFF800020);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorRojoVino,
        title: const Text(
          'Senda - Medición Offline',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.white),
            onPressed: _limpiarTodo,
            tooltip: 'Borrar todo',
          ),
        ],
      ),
      body: Stack(
        children: [
          // MAPA SATELITAL
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(14.0818, -87.2068),
              initialZoom: 16.0,
              onTap: _alHacerTapEnMapa,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                userAgentPackageName: 'com.tuempresa.senda',
              ),
              if (_puntosRuta.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(points: _puntosRuta, strokeWidth: 4.0, color: Colors.blueAccent),
                  ],
                ),
              PolygonLayer(
                polygons: [
                  for (var pol in _poligonosGuardados)
                    Polygon(points: pol, color: Colors.green.withOpacity(0.4), borderColor: Colors.green, borderStrokeWidth: 3),
                  if (_puntosPoligono.isNotEmpty)
                    Polygon(points: _puntosPoligono, color: Colors.amber.withOpacity(0.4), borderColor: Colors.amber, borderStrokeWidth: 3),
                ],
              ),
              MarkerLayer(
                markers: [
                  for (var p in _puntosRuta)
                    Marker(point: p, width: 20, height: 20, child: const Icon(Icons.location_pin, color: Colors.red, size: 24)),
                  for (var g in _puntosGeorreferenciados)
                    Marker(
                      point: LatLng(g['lat'], g['lng']),
                      width: 30,
                      height: 30,
                      child: const Icon(Icons.star, color: Colors.amber, size: 30),
                    ),
                ],
              ),
            ],
          ),

          // BARRA DE BÚSQUEDA CON LUPA (Superior)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            hintText: 'Buscar lugar por nombre...',
                            border: InputBorder.none,
                          ),
                          onSubmitted: (value) => _buscarLugarPorNombre(value),
                        ),
                      ),
                      if (_buscandoLugar)
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        IconButton(
                          icon: const Icon(Icons.send, color: colorRojoVino),
                          onPressed: () => _buscarLugarPorNombre(_searchController.text),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // PANEL FLOTANTE DE MÉTRICAS
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Text('Distancia', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                          Text('${_distanciaTotalKm.toStringAsFixed(2)} km', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                      Column(
                        children: [
                          const Text('Área', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                          Text('${_areaHectareas.toStringAsFixed(2)} ha', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                      Column(
                        children: [
                          const Text('Altura GPS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                          Text('${_alturaGpsActual.toStringAsFixed(1)} m', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // BOTÓN FLOTANTE PARA GUARDAR POLÍGONO (Si hay polígono activo)
          if (_puntosPoligono.length >= 3)
            Positioned(
              bottom: 100,
              left: 20,
              right: 20,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.all(12)),
                onPressed: () {
                  setState(() {
                    _poligonosGuardados.add(List.from(_puntosPoligono));
                    _puntosPoligono.clear();
                    _areaHectareas = 0.0;
                  });
                  _mostrarMensaje('¡Polígono guardado exitosamente!');
                },
                icon: const Icon(Icons.save, color: Colors.white),
                label: const Text('Guardar Polígono Actual', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),

          // BOTONES FLOTANTES LATERALES DERECHOS
          Positioned(
            right: 16,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Verde: Georreferenciar puntos
                FloatingActionButton(
                  heroTag: 'btnGeo',
                  backgroundColor: Colors.green,
                  onPressed: () => setState(() => _modoActivo = 'georreferencia'),
                  tooltip: 'Georreferenciar punto',
                  child: const Icon(Icons.add_location_alt, color: Colors.white),
                ),
                const SizedBox(height: 12),
                // 2. Vino: Centrar GPS
                FloatingActionButton(
                  heroTag: 'btnVinoCentro',
                  backgroundColor: colorRojoVino,
                  onPressed: () => _mapController.move(const LatLng(14.0818, -87.2068), 16.0),
                  tooltip: 'Centrar Ubicación',
                  child: const Icon(Icons.my_location, color: Colors.white),
                ),
                const SizedBox(height: 12),
                // 3. Amarillo: Trazar Líneas / Rutas
                FloatingActionButton(
                  heroTag: 'btnAmarillo',
                  backgroundColor: Colors.amber,
                  onPressed: () => setState(() => _modoActivo = 'linea'),
                  tooltip: 'Medir Distancia / Línea',
                  child: const Icon(Icons.show_chart, color: Colors.black87),
                ),
                const SizedBox(height: 12),
                // 4. Vino: Dibujar Polígonos
                FloatingActionButton(
                  heroTag: 'btnVinoPoligono',
                  backgroundColor: colorRojoVino,
                  onPressed: () => setState(() => _modoActivo = 'poligono'),
                  tooltip: 'Medir Polígono / Área',
                  child: const Icon(Icons.category, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}