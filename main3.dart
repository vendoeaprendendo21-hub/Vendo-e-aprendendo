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

// --- Utilitários de URL (Novo: Foco no GitHub) ---
String getMediaUrl(String fileName, String folder) {
  if (fileName.isEmpty || fileName.contains('ID_SOM')) return '';

  // Removido o "/refs/heads/" que causa erro no acesso direto aos arquivos
  const String baseUrl =
      "https://raw.githubusercontent.com/vendoeaprendendo21-hub/Vendo-e-aprendendo/main/media";

  return '$baseUrl/$folder/$fileName';
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
  final String jsonUrl =
      'https://raw.githubusercontent.com/vendoeaprendendo21-hub/Vendo-e-aprendendo/refs/heads/main/config1.json';
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
          if (mounted) setState(() => _categories = _parseJson(response.body));
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Category> _parseJson(String body) =>
      (json.decode(body) as List).map((c) => Category.fromJson(c)).toList();

  // OTIMIZAÇÃO: Download em paralelo dos itens da categoria
  Future<void> _downloadFullCategory(Category category) async {
    if (_downloadProgress[category.name] == 1.0) return;

    int total = category.items.length;
    int completed = 0;
    setState(() => _downloadProgress[category.name] = 0.01);

    await Future.wait(category.items.map((item) async {
      await _cacheMedia(item);
      completed++;
      if (mounted)
        setState(() => _downloadProgress[category.name] = completed / total);
    }));

    setState(() => _downloadProgress[category.name] = 1.0);
  }

  Future<void> _cacheMedia(Item item) async {
    try {
      final imgUrl = getMediaUrl(item.imageId, 'images');
      if (imgUrl.isNotEmpty)
        await precacheImage(CachedNetworkImageProvider(imgUrl), context);

      await Future.wait([
        if (item.soundPtId.isNotEmpty)
          DefaultCacheManager()
              .getSingleFile(getMediaUrl(item.soundPtId, 'audio/pt')),
        if (item.soundEnId.isNotEmpty)
          DefaultCacheManager()
              .getSingleFile(getMediaUrl(item.soundEnId, 'audio/en')),
        if (item.soundId.isNotEmpty)
          DefaultCacheManager()
              .getSingleFile(getMediaUrl(item.soundId, 'audio/real')),
      ]);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: const Text("Vendo e Aprendendo"), centerTitle: true),
      body: _isLoading && _categories == null
          ? const Center(child: CircularProgressIndicator())
          : _buildGrid(),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: _categories?.length ?? 0,
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
    await _cacheItemComplete(0);
    if (mounted) setState(() => _isLoadingFirst = false);
    _playFullSequence();
  }

  Future<void> _cacheItemComplete(int index) async {
    if (index < 0 || index >= widget.category.items.length) return;
    final item = widget.category.items[index];
    try {
      await precacheImage(
          CachedNetworkImageProvider(getMediaUrl(item.imageId, 'images')),
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
      final url = getMediaUrl(fileName, folder);
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
              imageUrl: getMediaUrl(widget.category.items[i].imageId, 'images'),
              fit: BoxFit.contain,
              memCacheWidth: 720, // Otimização de memória RAM
              placeholder: (_, __) =>
                  const Center(child: CircularProgressIndicator()),
              errorWidget: (_, __, ___) =>
                  const Icon(Icons.broken_image, color: Colors.white, size: 80),
            ),
          ),

          // --- NOME DO ITEM NO TOPO ---
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(20)),
                child: Text(current.nameItem.toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2)),
              ),
            ),
          ),

          Positioned(
            top: 50,
            left: 20,
            child: IconButton(
                icon:
                    const Icon(Icons.arrow_back, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context)),
          ),

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
            ]),
          ),
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
