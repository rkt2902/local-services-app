import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keeps an `.autoDispose` provider's last value alive for [ttl] after it
/// resolves, instead of disposing the moment its last widget stops
/// watching it. Re-watching the same provider (same family key) while
/// still within the window reuses the cached value — no new fetch.
///
/// This does NOT poll or refetch a value that's actively being watched: it
/// only affects what happens once nobody is watching. A screen left open
/// past [ttl] keeps showing its already-loaded data; only a fresh watch
/// after navigating away and back past the window triggers a new fetch.
///
/// An explicit `ref.invalidate(provider)` always wins regardless of how
/// much of the window remains: invalidation disposes the current state
/// immediately, which runs [Ref.onDispose] and cancels the pending timer,
/// so the next read re-runs `create` from scratch.
void cacheFor(Ref ref, Duration ttl) {
  final link = ref.keepAlive();
  final timer = Timer(ttl, link.close);
  ref.onDispose(timer.cancel);
}
