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

// --- CONFIGURAÇÃO DE URL GITHUB (SUBSTITUI O DRIVE) ---
// Note que usamos 'raw.githubusercontent.com' e removemos o '/refs/heads/' para evitar erros de cache do GitHub
String getGitHubUrl(String fileName, String folderPath) {
  if (fileName.isEmpty) return '';
  const String baseUrl =
      "https://raw.githubusercontent.com/vendoeaprendendo21-hub/Vendo-e-aprendendo/main/media";
  return '$baseUrl/$folderPath/$fileName';
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
  final String nameItem;
  final String imageId, soundId, soundEnId, soundPtId;
  Item({
    required this.nameItem,
    required this.imageId,
    required this.soundId,
    required this.soundEnId,
    required this.soundPtId,
  });

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      nameItem: json['name_item'] ?? '',
      imageId: json['image_id'] ?? '',
      soundId: json['sound_id'] ?? '',
      soundEnId: json['sound_en_id'] ?? '',
      soundPtId: json['sound_pt_id'] ?? '',
    );
  }
}

// --- Tela de Categorias ---
class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key});
  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  // URL do JSON também corrigida para o formato RAW direto
  final String jsonUrl =
      'https://raw.githubusercontent.com/vendoeaprendendo21-hub/Vendo-e-aprendendo/main/config1.json';
  List<Category>? _categories;
  bool _isLoading = true;
  final Map<String, double> _downloadProgress = {};

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('cached_json');
    if (cached != null) {
      setState(() {
        _categories = _parseJson(cached);
        _isLoading = false;
      });
    }
    await _checkUpdate(prefs);
  }

  Future<void> _checkUpdate(SharedPreferences prefs) async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) return;

      final response = await http
          .get(Uri.parse(jsonUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        if (response.body != prefs.getString('cached_json')) {
          await prefs.setString('cached_json', response.body);
          if (mounted)
            setState(() {
              _categories = _parseJson(response.body);
            });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Category> _parseJson(String body) {
    try {
      final decoded = json.decode(body) as List;
      return decoded.map((c) => Category.fromJson(c)).toList();
    } catch (e) {
      debugPrint("Erro no JSON: $e");
      return [];
    }
  }

  Future<void> _downloadFullCategory(Category category) async {
    if (_downloadProgress[category.name] == 1.0) return;
    int total = category.items.length;
    int completed = 0;
    setState(() => _downloadProgress[category.name] = 0.01);

    for (var item in category.items) {
      await _cacheItemComplete(item);
      completed++;
      if (mounted)
        setState(() => _downloadProgress[category.name] = completed / total);
    }
    setState(() => _downloadProgress[category.name] = 1.0);
  }

  // Centraliza o cache dos arquivos do GitHub
  Future<void> _cacheItemComplete(Item item) async {
    List<Future> tasks = [
      precacheImage(
          CachedNetworkImageProvider(getGitHubUrl(item.imageId, 'images')),
          context),
      if (item.soundPtId.isNotEmpty)
        DefaultCacheManager()
            .getSingleFile(getGitHubUrl(item.soundPtId, 'audio/pt')),
      if (item.soundEnId.isNotEmpty)
        DefaultCacheManager()
            .getSingleFile(getGitHubUrl(item.soundEnId, 'audio/en')),
      if (item.soundId.isNotEmpty)
        DefaultCacheManager()
            .getSingleFile(getGitHubUrl(item.soundId, 'audio/real')),
    ];
    try {
      await Future.wait(tasks);
    } catch (_) {}
  }

  Future<void> _clearAppCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_json');
    await DefaultCacheManager().emptyCache();
    setState(() {
      _downloadProgress.clear();
      _categories = null;
      _isLoading = true;
    });
    _initializeApp();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Vendo e Aprendendo"),
        centerTitle: true,
        actions: [
          IconButton(
              onPressed: _clearAppCache,
              icon: const Icon(Icons.refresh, color: Colors.red)),
        ],
      ),
      body: _isLoading && _categories == null
          ? const Center(child: CircularProgressIndicator())
          : _categories == null || _categories!.isEmpty
              ? Center(
                  child: ElevatedButton(
                      onPressed: _initializeApp,
                      child: const Text("Tentar Conectar")))
              : _buildGrid(),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: _categories!.length,
      itemBuilder: (context, i) {
        final cat = _categories![i];
        double progress = _downloadProgress[cat.name] ?? 0.0;
        return Card(
          color: cat.color,
          child: Stack(
            children: [
              InkWell(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ImageViewerScreen(category: cat))),
                child: Center(
                    child: Text(cat.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold))),
              ),
              Positioned(
                bottom: 5,
                right: 5,
                child: GestureDetector(
                  onTap: () => _downloadFullCategory(cat),
                  child: progress == 1.0
                      ? const Icon(Icons.check_circle,
                          color: Colors.greenAccent)
                      : Icon(Icons.download_for_offline,
                          color: Colors.white.withOpacity(0.7)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// --- Tela do Visualizador ---
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
    await _cacheItemComplete(widget.category.items[0]);
    if (mounted) setState(() => _isLoadingFirst = false);
    _playFullSequence();
  }

  Future<void> _cacheItemComplete(Item item) async {
    try {
      await precacheImage(
          CachedNetworkImageProvider(getGitHubUrl(item.imageId, 'images')),
          context);
    } catch (_) {}
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _seqId++;
    });
    _playFullSequence();
  }

  Future<void> _playFullSequence() async {
    int id = ++_seqId;
    _resetVisuals();
    final item = widget.category.items[_currentIndex];
    // Sequência: PT -> EN -> REAL
    if (await _playStep(item.soundPtId, 'audio/pt', pt: true, id: id)) {
      if (await _playStep(item.soundEnId, 'audio/en', en: true, id: id)) {
        await _playStep(item.soundId, 'audio/real', real: true, id: id);
      }
    }
  }

  Future<bool> _playStep(String fileName, String folder,
      {bool pt = false,
      bool en = false,
      bool real = false,
      required int id}) async {
    if (fileName.isEmpty || id != _seqId || !mounted) return false;
    setState(() {
      _isPt = pt;
      _isEn = en;
      _isReal = real;
    });
    _animController.repeat(reverse: true);
    try {
      final url = getGitHubUrl(fileName, folder);
      var file = await DefaultCacheManager().getFileFromCache(url);
      if (file != null) {
        await _audioPlayer.play(DeviceFileSource(file.file.path));
      } else {
        await _audioPlayer.play(UrlSource(url));
      }
      await _audioPlayer.onPlayerComplete.first;
    } catch (_) {}
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
              imageUrl:
                  getGitHubUrl(widget.category.items[i].imageId, 'images'),
              fit: BoxFit.contain,
              placeholder: (_, __) =>
                  const Center(child: CircularProgressIndicator()),
              errorWidget: (_, __, ___) =>
                  const Icon(Icons.broken_image, color: Colors.white, size: 80),
            ),
          ),
          // Nome do Item
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Text(current.nameItem.toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2)),
            ),
          ),
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
                _buildActionButton(
                    "🇧🇷",
                    _isPt,
                    () => _playStep(current.soundPtId, 'audio/pt',
                        pt: true, id: ++_seqId)),
                const SizedBox(width: 12),
                _buildActionButton(
                    "🇺🇸",
                    _isEn,
                    () => _playStep(current.soundEnId, 'audio/en',
                        en: true, id: ++_seqId)),
                const SizedBox(width: 12),
                _buildActionButton(
                    null,
                    _isReal,
                    () => _playStep(current.soundId, 'audio/real',
                        real: true, id: ++_seqId),
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
              color: anim ? Colors.orange : Colors.white24,
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
