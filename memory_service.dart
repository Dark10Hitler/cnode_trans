/// Абстракция "векторной памяти" локального ассистента.
///
/// Сейчас — [SimpleMemoryStore]: хранит реплики как обычный текст и
/// "ищет" по совпадению ключевых слов. Это ЧЕСТНАЯ заглушка, а не
/// настоящий векторный поиск — реальных embeddings тут нет.
///
/// КОГДА ПОДКЛЮЧИШЬ LLAMA.CPP: замени [SimpleMemoryStore] на реализацию,
/// которая считает embedding каждой реплики (например, через ту же
/// GGUF-модель или отдельную embedding-модель) и в [recall] делает
/// поиск по косинусной близости векторов вместо пересечения слов.
abstract class VectorMemoryService {
  Future<void> remember(String text);
  Future<List<String>> recall(String query, {int limit = 3});
}

class SimpleMemoryStore implements VectorMemoryService {
  final List<String> _entries = [];

  @override
  Future<void> remember(String text) async {
    if (text.trim().isEmpty) return;
    _entries.add(text.trim());
    if (_entries.length > 200) {
      _entries.removeAt(0);
    }
  }

  @override
  Future<List<String>> recall(String query, {int limit = 3}) async {
    final queryWords = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 3).toSet();
    if (queryWords.isEmpty || _entries.isEmpty) return [];

    final scored = <MapEntry<String, int>>[];
    for (final entry in _entries) {
      final entryWords = entry.toLowerCase().split(RegExp(r'\s+')).toSet();
      final overlap = queryWords.intersection(entryWords).length;
      if (overlap > 0) scored.add(MapEntry(entry, overlap));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(limit).map((e) => e.key).toList();
  }
}
