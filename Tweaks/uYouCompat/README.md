# uYouCompat

`uYouCompat` is the independently maintainable compatibility layer used by
uYouEnhanced. It is intentionally small:

- blocks player, Shorts, feed, and UI-fallback ad renderers;
- adapts the public YouTube model hooks used by current app releases;
- contains no account, subscription, activation, or remote entitlement system;
- does not replace or modify MiRO92's closed-source `uYou.dylib`.

The implementation is informed by the public ad-filtering approaches used by
YTLite, YouMod, and PoomSmart's YouTube tweaks, with defensive runtime checks
added for use on changing YouTube versions.
