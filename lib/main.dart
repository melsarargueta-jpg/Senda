import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching_plus/flutter_map_tile_caching_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

const Color rojoVino = Color(0xFF800020);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SendaApp());
}

class SendaApp extends StatelessWidget {
  const SendaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Senda',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: rojoVino,
          primary: rojoVino,
        ),
        useMaterial3: true,
      ),
      home: const MapaSendaPage(),
    );
  }
}

enum ModoDibujo { ninguno, ruta, poligono }

class MapaSendaPage extends StatefulWidget {
  const MapaSendaPage({super.key});

  @override
  State<MapaSendaPage> createState() => _MapaSendaPageState();
}

class _MapaSendaPageState extends State<MapaSendaPage> {
  final MapController _mapController = MapController();
  final List<LatLng> _puntos = [];
  
  ModoDibujo _modoActual = ModoDibujo.ninguno;
  
  LatLng? _posicionActual;
  double? _altitudActual;
  double _distanciaTotal = 0.0;
  double _areaTotalM2 = 0.0;
  
  StreamSubscription<Position>? _positionStream;
  bool _seguirUsuario = true;

  @override
  void initState() {
    super.initState();
    _iniciarSeguimientoGPS();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  // --- SEGUIMIENTO GPS OFFLINE (Vía Hardware GPS) ---

  Future<void> _iniciarSeguimientoGPS() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      ),
    ).listen((Position pos) {
      final nuevaPos = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _posicionActual = nuevaPos;
        _altitudActual = pos.altitude;
      });

      if (_seguirUsuario) {
        _mapController.move(nuevaPos, _mapController.camera.zoom);
      }
    });
  }

  // Agregar punto en la ubicación actual del GPS
  void _agregarPuntoDesdeGPS() {
    if (_posicionActual != null && _modoActual != ModoDibujo.ninguno) {
      setState(() {
        _puntos.add(_posicionActual!);
        _calcularMetricas();
      });
    }
  }

  // --- NAVEGACIÓN DIRECTA POR COORDENADAS (100% Offline) ---

  void _mostrarDialogoCoordenadas() {
    final latController = TextEditingController();
    final lonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ir a Coordenadas'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: latController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(
                labelText: 'Latitud',
                hintText: 'ej. 14.0723',
              ),
            ),
            TextField(
              controller: lonController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(
                labelText: 'Longitud',
                hintText: 'ej. -87.1921',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: rojoVino,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final lat = double.tryParse(latController.text);
              final lon = double.tryParse(lonController.text);
              if (lat != null && lon != null) {
                final destino = LatLng(lat, lon);
                _mapController.move(destino, 16.0);

                // Si estamos en modo dibujo, agrega la coordenada ingresada a la ruta/polígono
                if (_modoActual != ModoDibujo.ninguno) {
                  setState(() {
                    _puntos.add(destino);
                    _calcularMetricas();
                  });
                }
                Navigator.pop(context);
              }
            },
            child: const Text('Ir / Marcar'),
          ),
        ],
      ),
    );
  }

  // --- CÁLCULOS MATEMÁTICOS LOCALES (Distancia y Área) ---

  void _calcularMetricas() {
    if (_puntos.length < 2) {
      _distanciaTotal = 0.0;
      _areaTotalM2 = 0.0;
      return;
    }

    // Distancia
    const Distance distanceCalc = Distance();
    double acumulado = 0.0;
    for (int i = 0; i < _puntos.length - 1; i++) {
      acumulado += distanceCalc.as(LengthUnit.Meter, _puntos[i], _puntos[i + 1]);
    }
    _distanciaTotal = acumulado;

    // Área esférica de Polígono
    if (_puntos.length >= 3 && _modoActual == ModoDibujo.poligono) {
      double area = 0.0;
      int j = _puntos.length - 1;
      const double radioTierra = 6371000.0;

      for (int i = 0; i < _puntos.length; i++) {
        double lat1 = _puntos[j].latitude * pi / 180;
        double lon1 = _puntos[j].longitude * pi / 180;
        double lat2 = _puntos[i].latitude * pi / 180;
        double lon2 = _puntos[i].longitude * pi / 180;

        area += (lon2 - lon1) * (2 + sin(lat1) + sin(lat2));
        j = i;
      }
      area = (area * radioTierra * radioTierra / 2.0).abs();
      _areaTotalM2 = area;
    } else {
      _areaTotalM2 = 0.0;
    }
  }

  void _alTocarMapa(TapPosition tapPosition, LatLng point) {
    if (_modoActual == ModoDibujo.ninguno) return;

    setState(() {
      _puntos.add(point);
      _calcularMetricas();
    });
  }

  void _limpiarMapa() {
    setState(() {
      _puntos.clear();
      _distanciaTotal = 0.0;
      _areaTotalM2 = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Senda - Medición Offline', style: TextStyle(color: Colors.white)),
        backgroundColor: rojoVino,
        actions: [
          IconButton(
            icon: const Icon(Icons.pin_drop, color: Colors.white),
            tooltip: 'Ir / Marcar Coordenadas',
            onPressed: _mostrarDialogoCoordenadas,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.white),
            tooltip: 'Limpiar Mapa',
            onPressed: _limpiarMapa,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(14.0723, -87.1921),
              initialZoom: 13.0,
              onTap: _alTocarMapa,
            ),
            children: [
              // Capa de Mapa Satelital
              TileLayer(
                urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                userAgentPackageName: 'com.ejemplo.senda',
                errorTileCallback: (tile, error, stackTrace) {
                  // Previene fallos visuales si se pierde la conexión
                },
              ),

              // Capa de Polígono
              if (_modoActual == ModoDibujo.poligono && _puntos.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _puntos,
                      color: rojoVino.withOpacity(0.35),
                      borderColor: rojoVino,
                      borderStrokeWidth: 3,
                    ),
                  ],
                ),

              // Capa de Ruta / Línea de Distancia
              if (_puntos.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _puntos,
                      strokeWidth: 4.0,
                      color: rojoVino,
                    ),
                  ],
                ),

              // Marcadores de los vértices seleccionados
              MarkerLayer(
                markers: _puntos
                    .map(
                      (p) => Marker(
                        point: p,
                        width: 14,
                        height: 14,
                        child: Container(
                          decoration: BoxDecoration(
                            color: rojoVino,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),

              // Puntero de ubicación GPS en tiempo real
              if (_posicionActual != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _posicionActual!,
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // Panel Superior Informativo de Métricas y Altitud
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Card(
              color: Colors.white.withOpacity(0.95),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text('Distancia', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        Text('${(_distanciaTotal / 1000).toStringAsFixed(2)} km'),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('Área', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        Text('${(_areaTotalM2 / 10000).toStringAsFixed(2)} ha'),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('Altura GPS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        Text(_altitudActual != null ? '${_altitudActual!.toStringAsFixed(1)} m' : '--'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),

      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Botón Verde: Marca el punto exacto donde estás parado vía GPS
          if (_modoActual != ModoDibujo.ninguno)
            FloatingActionButton.small(
              heroTag: 'btnAddGPS',
              backgroundColor: Colors.green,
              onPressed: _agregarPuntoDesdeGPS,
              child: const Icon(Icons.add_location, color: Colors.white),
            ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'btnUbicacion',
            backgroundColor: _seguirUsuario ? rojoVino : Colors.grey,
            onPressed: () {
              setState(() {
                _seguirUsuario = !_seguirUsuario;
              });
              if (_posicionActual != null) {
                _mapController.move(_posicionActual!, 16.0);
              }
            },
            child: const Icon(Icons.my_location, color: Colors.white),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'btnRuta',
            backgroundColor: _modoActual == ModoDibujo.ruta ? Colors.amber : rojoVino,
            onPressed: () {
              setState(() {
                _modoActual = _modoActual == ModoDibujo.ruta ? ModoDibujo.ninguno : ModoDibujo.ruta;
              });
            },
            child: const Icon(Icons.timeline, color: Colors.white),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'btnPoligono',
            backgroundColor: _modoActual == ModoDibujo.poligono ? Colors.amber : rojoVino,
            onPressed: () {
              setState(() {
                _modoActual = _modoActual == ModoDibujo.poligono ? ModoDibujo.ninguno : ModoDibujo.poligono;
              });
            },
            child: const Icon(Icons.polyline, color: Colors.white),
          ),
        ],
      ),
    );
  }
}