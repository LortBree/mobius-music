import 'dart:collection';

/// A small least-recently-used map.
///
/// Used for per-row artwork: each entry holds a track's raw embedded cover
/// bytes (often several MB), so an unbounded map grows with every track a
/// long queue or playlist has ever shown.
class LruCache<K, V> {
  LruCache(this.capacity) : assert(capacity > 0);

  final int capacity;
  final LinkedHashMap<K, V> _entries = LinkedHashMap<K, V>();

  bool containsKey(K key) => _entries.containsKey(key);

  /// The cached value, marking it most recently used. Returns null both for
  /// a miss and for a cached null; use [containsKey] to tell them apart.
  V? get(K key) {
    if (!_entries.containsKey(key)) return null;
    final value = _entries.remove(key) as V;
    _entries[key] = value;
    return value;
  }

  void put(K key, V value) {
    _entries.remove(key);
    _entries[key] = value;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() => _entries.clear();

  int get length => _entries.length;
}
