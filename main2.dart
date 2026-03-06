import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'dart:convert';
import 'dart:async';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vendo e Aprendendo',
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
          useMaterial3: true),
      home: const CategoryScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- Utilitários ---
String getDriveUrl(String id) {
  if (id.isEmpty) return '';
  if (id.startsWith('http')) return id;
  return 'https://drive.google.com/uc?export=download&id=$id';
}

// --- Modelos ---
class Category {
  final String name;
  final Color color;
  final List<Item> items;
  Category({required this.name, required this.color, required this.items});

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      name: json['name'] ?? '',
      color: Color(
          int.parse((json['color'] ?? '#FF0000').replaceAll('#', '0xff'))),
      items:
          (json['items'] as List?)?.map((i) => Item.fromJson(i)).toList() ?? [],
    );
  }
}

class Item {
  final String imageId, soundId, soundEnId, soundPtId;
  Item(
      {required this.imageId,
      required this.soundId,
      required this.soundEnId,
      required this.soundPtId});

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      imageId: json['image_id'] ?? '',
      soundId: json['sound_id'] ?? '',
      soundEnId: json['sound_en_id'] ?? '',
      soundPtId: json['sound_pt_id'] ?? '',
    );
  }
}

// --- Tela de Categorias com Auto-Update ---
class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key});
  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  final String jsonUrl =
      'https://raw.githubusercontent.com/vendoeaprendendo21-hub/Vendo-e-aprendendo/refs/heads/main/config.json';
  List<Category>? _categories;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  /// Fluxo: Carrega Cache -> Busca Internet -> Se novo, atualiza
  Future<void> _initializeApp() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Tenta carregar o que já está salvo primeiro
    final cached = prefs.getString('cached_json');
    if (cached != null) {
      setState(() {
        _categories = _parseJson(cached);
        _isLoading = false;
      });
    }

    // 2. Busca atualização na internet
    await _checkUpdate(prefs);
  }

  Future<void> _checkUpdate(SharedPreferences prefs) async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      if (_categories == null) {
        setState(() =>
            _isLoading = false); // Para o loading se estiver totalmente offline
      }
      return;
    }

    try {
      final response = await http
          .get(Uri.parse(jsonUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final String currentJson = response.body;
        final String? savedJson = prefs.getString('cached_json');

        // Se o que baixou é diferente do que temos salvo, atualiza
        if (currentJson != savedJson) {
          await prefs.setString('cached_json', currentJson);
          setState(() {
            _categories = _parseJson(currentJson);
            _isLoading = false;
          });
          debugPrint("App atualizado com novos dados do JSON!");
        }
      }
    } catch (e) {
      debugPrint("Erro ao verificar atualizações: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Category> _parseJson(String body) =>
      (json.decode(body) as List).map((c) => Category.fromJson(c)).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Vendo e Aprendendo"),
        centerTitle: true,
        actions: [
          // Ícone discreto para indicar atualização manual se o usuário quiser
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _checkUpdate(
                  SharedPreferences.getInstance() as SharedPreferences))
        ],
      ),
      body: _isLoading && _categories == null
          ? const Center(child: CircularProgressIndicator())
          : _categories == null || _categories!.isEmpty
              ? _buildErrorUI()
              : _buildGrid(),
    );
  }

  Widget _buildErrorUI() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off, size: 60, color: Colors.grey),
          const SizedBox(height: 10),
          const Text("Precisa de internet para o primeiro acesso."),
          ElevatedButton(
              onPressed: _initializeApp, child: const Text("Tentar Novamente"))
        ],
      ),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10),
      itemCount: _categories!.length,
      itemBuilder: (context, i) => Card(
        color: _categories![i].color,
        child: InkWell(
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      ImageViewerScreen(category: _categories![i]))),
          child: Center(
              child: Text(_categories![i].name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold))),
        ),
      ),
    );
  }
}

// --- Tela do Visualizador (Mantém a lógica de download paralelo e barra de progresso) ---
class ImageViewerScreen extends StatefulWidget {
  final Category category;
  const ImageViewerScreen({super.key, required this.category});
  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  int _currentIndex = 0;
  bool _isLoadingFirst = true;
  bool _isDownloadingNext = false;

  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  bool _isPt = false, _isEn = false, _isReal = false;
  int _seqId = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _scaleAnim = Tween(begin: 1.0, end: 1.2).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeInOut));
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await _cacheItemComplete(0);
    if (mounted) setState(() => _isLoadingFirst = false);
    _playFullSequence();
    _preloadNext(1);
  }

  Future<void> _preloadNext(int index) async {
    if (index < 0 || index >= widget.category.items.length) return;
    if (mounted) setState(() => _isDownloadingNext = true);
    await _cacheItemComplete(index);
    if (mounted) setState(() => _isDownloadingNext = false);
  }

  Future<void> _cacheItemComplete(int index) async {
    if (index < 0 || index >= widget.category.items.length) return;
    final item = widget.category.items[index];
    List<Future> downloads = [];
    downloads.add(precacheImage(
        CachedNetworkImageProvider(getDriveUrl(item.imageId)), context));
    for (var id in [item.soundPtId, item.soundEnId, item.soundId]) {
      if (id.isNotEmpty)
        downloads.add(DefaultCacheManager().getSingleFile(getDriveUrl(id)));
    }
    try {
      await Future.wait(downloads);
    } catch (e) {
      debugPrint("Erro cache: $e");
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _seqId++;
    });
    _playFullSequence();
    _preloadNext(index + 1);
  }

  Future<void> _playFullSequence() async {
    int id = ++_seqId;
    _resetVisuals();
    final item = widget.category.items[_currentIndex];
    if (await _playStep(item.soundPtId, pt: true, id: id)) {
      if (await _playStep(item.soundEnId, en: true, id: id)) {
        await _playStep(item.soundId, real: true, id: id);
      }
    }
    if (id == _seqId) _resetVisuals();
  }

  Future<bool> _playStep(String soundId,
      {bool pt = false,
      bool en = false,
      bool real = false,
      required int id}) async {
    if (soundId.isEmpty || id != _seqId || !mounted) return false;
    setState(() {
      _isPt = pt;
      _isEn = en;
      _isReal = real;
    });
    _animController.repeat(reverse: true);
    try {
      var file =
          await DefaultCacheManager().getFileFromCache(getDriveUrl(soundId));
      if (file != null) {
        await _audioPlayer.play(DeviceFileSource(file.file.path));
      } else {
        await _audioPlayer.play(UrlSource(getDriveUrl(soundId)));
      }
      await _audioPlayer.onPlayerComplete.first;
    } catch (e) {
      debugPrint("Erro áudio: $e");
    }
    _animController.stop();
    _animController.reset();
    return id == _seqId;
  }

  void _resetVisuals() {
    if (!mounted) return;
    setState(() {
      _isPt = false;
      _isEn = false;
      _isReal = false;
    });
    _animController.reset();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _animController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingFirst)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final current = widget.category.items[_currentIndex];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.category.items.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (_, i) => CachedNetworkImage(
              imageUrl: getDriveUrl(widget.category.items[i].imageId),
              fit: BoxFit.contain,
              placeholder: (_, __) =>
                  const Center(child: CircularProgressIndicator()),
              errorWidget: (_, __, ___) =>
                  const Icon(Icons.broken_image, color: Colors.white, size: 80),
            ),
          ),
          if (_isDownloadingNext)
            const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                    backgroundColor: Colors.transparent,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
                    minHeight: 4)),
          Positioned(
              top: 50,
              left: 20,
              child: IconButton(
                  icon: const Icon(Icons.arrow_back,
                      color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context))),
          Positioned(
              top: 50,
              right: 20,
              child: Row(children: [
                _buildActionButton("🇧🇷", _isPt,
                    () => _playStep(current.soundPtId, pt: true, id: ++_seqId)),
                const SizedBox(width: 12),
                _buildActionButton("🇺🇸", _isEn,
                    () => _playStep(current.soundEnId, en: true, id: ++_seqId)),
                const SizedBox(width: 12),
                _buildActionButton(null, _isReal,
                    () => _playStep(current.soundId, real: true, id: ++_seqId),
                    icon: Icons.volume_up),
              ])),
        ],
      ),
    );
  }

  Widget _buildActionButton(String? label, bool anim, VoidCallback onTap,
      {IconData? icon}) {
    return GestureDetector(
      onTap: onTap,
      child: ScaleTransition(
        scale: anim ? _scaleAnim : const AlwaysStoppedAnimation(1.0),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: anim ? Colors.orange.withOpacity(0.8) : Colors.white24,
              border: Border.all(
                  color: anim ? Colors.white : Colors.transparent, width: 2)),
          child: icon != null
              ? Icon(icon, color: Colors.white, size: 32)
              : Text(label!, style: const TextStyle(fontSize: 32)),
        ),
      ),
    );
  }
}
