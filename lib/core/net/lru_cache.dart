/// Small LRU cache with per-entry TTL. Injectable clock for tests.
class LruCache<K, V> {
  LruCache({required this.capacity, required this.ttl, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final int capacity;
  final Duration ttl;
  final DateTime Function() _clock;
  final _map = <K, ({V value, DateTime expires})>{};

  int get length => _map.length;

  V? get(K key) {
    final e = _map.remove(key);
    if (e == null) return null;
    if (!_clock().isBefore(e.expires)) return null;
    _map[key] = e; // re-insert = most recently used
    return e.value;
  }

  void put(K key, V value, {Duration? ttl}) {
    _map.remove(key);
    _map[key] = (value: value, expires: _clock().add(ttl ?? this.ttl));
    while (_map.length > capacity) {
      _map.remove(_map.keys.first);
    }
  }

  void clear() => _map.clear();
}
