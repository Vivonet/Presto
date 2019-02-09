#Breaking Changes

* **2019-02-09** Deprecated `objectOfClass:` and `arrayOfClass:`. These have been replaced with a more generalized `withClass:atDepth:` allowing for the supplied native class to take effect at a specific depth in the tree, instantiating generic `NSArray`/`NSDictionary` objects prior to that point. Note that the given depth must coincide with a JSON object (dictionary) in the payload. A depth of `0` will yield the previous functionality.

* **2015-09-03** Renamed `load` to `reload` to better capture what this method represents. This method can be called at any time to reload an object on demand, whereas the naming `load` implies that it only should be called once. Since calling `reload` is not explicitly necessary the first time you use an object, it tends to be used exclusively for explicit reloading anyway. `loadFrom:` was also renamed to `loadWith:`.
