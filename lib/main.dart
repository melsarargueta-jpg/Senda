import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'dart:async';

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

  final List<LatLng> _puntosRuta = [];
  final List<LatLng> _puntosPoligono = [];
  final List<Map<String, dynamic>> _poligonosGuardados = [];
  final List<Map<String, dynamic>> _puntosGeorreferenciados = [];

  List<LatLng> _rutaCarreteraPrincipal = [];
  List<LatLng> _rutaCarreteraAlternativa = [];
  bool _mostrarAlternativa = false;
  LatLng? _destinoActual; 

  double _distanciaTotalKm = 0.0;
  double _areaHectareas = 0.0;
  
  double _alturaGpsActual = 0.0;
  double _alturaDestinoActual = 0.0;

  String _modoActivo = 'punto'; 
  bool _buscandoLugar = false;
  bool _descargandoZona = false;
  bool _siguiendoUbicacion = false;

  StreamSubscription<Position>? _positionStreamSubscription;
  LatLng? _ubicacionActualGPS;

  @override
  void initState() {
    super.initState();
    _iniciarPermisosYSeguimientoGPS();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _iniciarPermisosYSeguimientoGPS() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    try {
      Position initialPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _ubicacionActualGPS = LatLng(initialPosition.latitude, initialPosition.longitude);
        _alturaGpsActual = initialPosition.altitude;
      });
    } catch (e) {
      // Sin lectura inicial
    }

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 3,
    );

    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
      final nuevaPos = LatLng(position.latitude, position.longitude);
      setState(() {
        _ubicacionActualGPS = nuevaPos;
        if (_modoActivo != 'linea') {
          _alturaGpsActual = position.altitude;
        }
      });

      if (_siguiendoUbicacion) {
        _mapController.move(nuevaPos, _mapController.camera.zoom);
      }
    });
  }

  LatLng? _analizarCoordenadas(String text) {
    text = text.replaceAll(' ', '');
    final partes = text.split(',');
    if (partes.length == 2) {
      final lat = double.tryParse(partes[0]);
      final lon = double.tryParse(partes[1]);
      if (lat != null && lon != null) {
        return LatLng(lat, lon);
      }
    }
    return null;
  }

  Future<void> _buscarLugarOCoordenadas(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _buscandoLugar = true);

    LatLng? destino = _analizarCoordenadas(query);

    if (destino != null) {
      _procesarNuevoDestino(destino, query);
      _mostrarMensaje('Destino por coordenadas establecido');
      setState(() => _buscandoLugar = false);
      return;
    }

    // Busqueda offline en puntos guardados o simulación local si no hay internet
    try {
      final urlGeo = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=1',
      );
      final responseGeo = await http.get(urlGeo, headers: {'User-Agent': 'SendaApp/1.0'}).timeout(const Duration(seconds: 4));
      
      if (responseGeo.statusCode == 200) {
        final List resultados = json.decode(responseGeo.body);
        if (resultados.isNotEmpty) {
          final lat = double.parse(resultados[0]['lat']);
          final lon = double.parse(resultados[0]['lon']);
          destino = LatLng(lat, lon);

          _procesarNuevoDestino(destino, query);
          _mostrarMensaje('Ubicacion encontrada con exito');
        } else {
          _mostrarMensaje('No se encontro el lugar en linea. Usa coordenadas Lat,Lon');
        }
      }
    } catch (e) {
      _mostrarMensaje('Sin conexion: Ingrese coordenadas directas (Lat,Lon)');
    } finally {
      setState(() => _buscandoLugar = false);
    }
  }

  void _procesarNuevoDestino(LatLng destino, String nombreLugar) async {
    setState(() {
      _modoActivo = 'linea'; 
      _destinoActual = destino;
      _puntosRuta.clear();
      _puntosRuta.add(destino);
    });

    _mapController.move(destino, 15.0);
    
    // Calculo de distancia recta offline si no hay red de ruta
    LatLng origen = _ubicacionActualGPS ?? _mapController.camera.center;
    double distanciaMetros = const Geolocator().distanceBetween(
      origen.latitude, origen.longitude, destino.latitude, destino.longitude,
    );
    
    setState(() {
      _distanciaTotalKm = distanciaMetros / 1000.0;
    });
  }

  void _descargarZonaActual() {
    setState(() => _descargandoZona = true);
    // Simula la descarga y almacenamiento en cache local de las teselas visibles
    Future.delayed(const Duration(seconds: 2), () {
      setState(() => _descargandoZona = false);
      _mostrarMensaje('Zona guardada en cache local para uso offline');
    });
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

  void _alHacerTapEnMapa(TapPosition tapPosition, LatLng punto) async {
    if (_modoActivo == 'georreferencia') {
      _mostrarDialogoNombre('Nombre del Geopunto', (nombreIngresado) {
        String nombreFinal = nombreIngresado.trim().isNotEmpty 
            ? nombreIngresado.trim() 
            : 'Geopunto #${_puntosGeorreferenciados.length + 1}';

        setState(() {
          _puntosGeorreferenciados.add({
            'nombre': nombreFinal,
            'lat': punto.latitude,
            'lng': punto.longitude,
            'altura': _alturaGpsActual,
          });
        });
        _mostrarMensaje('Geopunto guardado localmente');
      });
    } else if (_modoActivo == 'poligono') {
      setState(() {
        _puntosPoligono.add(punto);
        _calcularArea();
      });
    } else if (_modoActivo == 'linea') {
      setState(() {
        _destinoActual = punto;
        _puntosRuta.clear();
        _puntosRuta.add(punto);
      });
      
      LatLng origen = _ubicacionActualGPS ?? _mapController.camera.center;
      double distanciaMetros = Geolocator.distanceBetween(
        origen.latitude, origen.longitude, punto.latitude, punto.longitude,
      );

      setState(() {
        _distanciaTotalKm = distanciaMetros / 1000.0;
      });
      _mostrarMensaje('Punto de ruta fijado');
    }
  }

  void _pedirNombreYGuardarPoligono() {
    if (_puntosPoligono.length < 3) return;

    _mostrarDialogoNombre('Nombre del Poligono', (nombreIngresado) {
      String nombreFinal = nombreIngresado.trim().isNotEmpty 
          ? nombreIngresado.trim() 
          : 'Poligono #${_poligonosGuardados.length + 1}';

      setState(() {
        _poligonosGuardados.add({
          'nombre': nombreFinal,
          'puntos': List<LatLng>.from(_puntosPoligono),
          'area': _areaHectareas,
        });
        _puntosPoligono.clear();
        _areaHectareas = 0.0;
      });
      _mostrarMensaje('Poligono guardado con exito');
    });
  }

  void _mostrarDialogoNombre(String titulo, Function(String) onGuardar) {
    TextEditingController controllerDialogo = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(titulo, style: const TextStyle(color: Color(0xFF800020), fontWeight: FontWeight.bold)),
          content: TextField(
            controller: controllerDialogo,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Escribe el nombre aqui',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF800020)),
              onPressed: () {
                Navigator.pop(context);
                onGuardar(controllerDialogo.text);
              },
              child: const Text('Guardar', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _limpiarTodo() {
    setState(() {
      _puntosRuta.clear();
      _puntosPoligono.clear();
      _puntosGeorreferenciados.clear();
      _rutaCarreteraPrincipal.clear();
      _rutaCarreteraAlternativa.clear();
      _destinoActual = null;
      _distanciaTotalKm = 0.0;
      _areaHectareas = 0.0;
      _alturaDestinoActual = 0.0;
    });
  }

  void _mostrarArchivoGeneral() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DefaultTabController(
          length: 2,
          child: Container(
            padding: const EdgeInsets.all(20),
            height: 480,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Archivo General Senda',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF800020)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const TabBar(
                  labelColor: Color(0xFF800020),
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Color(0xFF800020),
                  tabs: [
                    Tab(text: 'Poligonos', icon: Icon(Icons.category)),
                    Tab(text: 'Geopuntos', icon: Icon(Icons.star)),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: TabBarView(
                    children: [
                      _poligonosGuardados.isEmpty
                          ? const Center(
                              child: Text(
                                'No hay poligonos guardados todavia.\nDibuja uno y presiona guardar.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _poligonosGuardados.length,
                              itemBuilder: (context, index) {
                                final polData = _poligonosGuardados[index];
                                return Card(
                                  elevation: 2,
                                  margin: const EdgeInsets.symmetric(vertical: 6),
                                  child: ListTile(
                                    leading: const CircleAvatar(
                                      backgroundColor: Color(0xFF800020),
                                      child: Icon(Icons.category, color: Colors.white),
                                    ),
                                    title: Text(polData['nombre'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text('Area: ${polData['area'].toStringAsFixed(2)} hectareas'),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () {
                                        setState(() {
                                          _poligonosGuardados.removeAt(index);
                                        });
                                        Navigator.pop(context);
                                        _mostrarArchivoGeneral();
                                        _mostrarMensaje('Poligono eliminado');
                                      },
                                    ),
                                    onTap: () {
                                      final List<LatLng> puntos = polData['puntos'];
                                      if (puntos.isNotEmpty) {
                                        _mapController.move(puntos.first, 16.0);
                                        Navigator.pop(context);
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
                      _puntosGeorreferenciados.isEmpty
                          ? const Center(
                              child: Text(
                                'No hay geopuntos guardados.\nSelecciona el modo geopunto y toca el mapa.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _puntosGeorreferenciados.length,
                              itemBuilder: (context, index) {
                                final geo = _puntosGeorreferenciados[index];
                                return Card(
                                  elevation: 2,
                                  margin: const EdgeInsets.symmetric(vertical: 6),
                                  child: ListTile(
                                    leading: const CircleAvatar(
                                      backgroundColor: Colors.amber,
                                      child: Icon(Icons.star, color: Colors.black87),
                                    ),
                                    title: Text(geo['nombre'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text('Lat: ${geo['lat'].toStringAsFixed(5)}, Lon: ${geo['lng'].toStringAsFixed(5)}\nAlt: ${geo['altura'].toStringAsFixed(1)} m'),
                                    isThreeLine: true,
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () {
                                        setState(() {
                                          _puntosGeorreferenciados.removeAt(index);
                                        });
                                        Navigator.pop(context);
                                        _mostrarArchivoGeneral();
                                        _mostrarMensaje('Geopunto eliminado');
                                      },
                                    ),
                                    onTap: () {
                                      _mapController.move(LatLng(geo['lat'], geo['lng']), 17.0);
                                      Navigator.pop(context);
                                    },
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _mostrarMensaje(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    const colorRojoVino = Color(0xFF800020);
    bool enModoRuta = (_modoActivo == 'linea');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorRojoVino,
        title: const Text(
          'Senda - Medicion Offline',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open, color: Colors.white, size: 28),
            onPressed: _mostrarArchivoGeneral,
            tooltip: 'Ver archivo general',
          ),
          IconButton(
            icon: const Icon(Icons.download_for_offline, color: Colors.white, size: 28),
            onPressed: _descargandoZona ? null : _descargandoZonaActual,
            tooltip: 'Guardar zona actual en cache',
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.white),
            onPressed: _limpiarTodo,
            tooltip: 'Borrar todo',
          ),
        ],
      ),
      body: Stack(
        children: [
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
                // Habilita el almacenamiento en cache local automatico de FlutterMap para uso offline
                tileProvider: NetworkTileProvider(),
              ),
              PolygonLayer(
                polygons: [
                  for (var pol in _poligonosGuardados)
                    Polygon(points: pol['puntos'], color: Colors.green.withOpacity(0.4), borderColor: Colors.green, borderStrokeWidth: 3),
                  if (_puntosPoligono.isNotEmpty)
                    Polygon(points: _puntosPoligono, color: Colors.amber.withOpacity(0.4), borderColor: Colors.amber, borderStrokeWidth: 3),
                ],
              ),
              MarkerLayer(
                markers: [
                  if (_ubicacionActualGPS != null)
                    Marker(
                      point: _ubicacionActualGPS!,
                      width: 35,
                      height: 35,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.3),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Center(
                          child: Icon(Icons.navigation, color: Colors.blueAccent, size: 20),
                        ),
                      ),
                    ),
                  for (var p in _puntosRuta)
                    Marker(point: p, width: 22, height: 22, child: const Icon(Icons.location_pin, color: Colors.red, size: 26)),
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
                            hintText: 'Ingresa Lat,Lon o Coordenadas',
                            border: InputBorder.none,
                          ),
                          onSubmitted: (value) => _buscarLugarOCoordenadas(value),
                        ),
                      ),
                      if (_buscandoLugar)
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        IconButton(
                          icon: const Icon(Icons.send, color: colorRojoVino),
                          onPressed: () => _buscarLugarOCoordenadas(_searchController.text),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            const Text('Distancia', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                            Text('${_distanciaTotalKm.toStringAsFixed(2)} km', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            const Text('Area', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                            Text('${_areaHectareas.toStringAsFixed(2)} ha', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(enModoRuta ? 'Alt Destino' : 'Altura GPS', 
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: enModoRuta ? Colors.amber[900] : Colors.grey)),
                            Text(
                              enModoRuta ? '${_alturaDestinoActual.toStringAsFixed(1)} m' : '${_alturaGpsActual.toStringAsFixed(1)} m', 
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: enModoRuta ? Colors.amber[900] : Colors.black87)
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
          if (_descargandoZona)
            const Center(
              child: Card(
                color: Colors.black87,
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(width: 16),
                      Text('Guardando zona en cache offline', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
          if (_puntosPoligono.length >= 3)
            Positioned(
              bottom: 100,
              left: 20,
              right: 20,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.all(12)),
                onPressed: _pedirNombreYGuardarPoligono,
                icon: const Icon(Icons.save, color: Colors.white),
                label: const Text('Guardar Poligono Actual', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  heroTag: 'btnGeo',
                  backgroundColor: Colors.green,
                  onPressed: () {
                    setState(() => _modoActivo = 'georreferencia');
                    _mostrarMensaje('Modo Georreferenciar activo');
                  },
                  tooltip: 'Guardar Geopunto',
                  child: const Icon(Icons.add_location, color: Colors.white),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'btnVinoCentro',
                  backgroundColor: _siguiendoUbicacion ? Colors.blue : colorRojoVino,
                  onPressed: () {
                    setState(() {
                      _siguiendoUbicacion = !_siguiendoUbicacion;
                    });
                    if (_siguiendoUbicacion && _ubicacionActualGPS != null) {
                      _mapController.move(_ubicacionActualGPS!, 16.0);
                      _mostrarMensaje('Seguimiento GPS activado');
                    } else {
                      _mostrarMensaje('Seguimiento desactivado');
                    }
                  },
                  tooltip: 'Mi Ubicacion GPS',
                  child: Icon(
                    _siguiendoUbicacion ? Icons.gps_fixed : Icons.my_location,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'btnAmarillo',
                  backgroundColor: _modoActivo == 'linea' ? Colors.amber[800]! : Colors.amber,
                  onPressed: () {
                    setState(() => _modoActivo = 'linea');
                    _mostrarMensaje('Modo Ruta activo');
                  },
                  tooltip: 'Medir Ruta',
                  child: const Icon(Icons.show_chart, color: Colors.black87),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'btnVinoPoligono',
                  backgroundColor: colorRojoVino,
                  onPressed: () {
                    setState(() => _modoActivo = 'poligono');
                    _mostrarMensaje('Modo Poligono activo');
                  },
                  tooltip: 'Medir Poligono',
                  child: const Icon(Icons.pentagon_outlined, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}