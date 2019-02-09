# Breaking Changes

#### 2019-02-09
* Deprecated `objectOfClass:` and `arrayOfClass:`. These have been replaced with a more generalized `withClass:atDepth:` allowing for the supplied native class to take effect only at a specific depth in the tree, instantiating generic `NSArray`/`NSDictionary` objects prior to that point. Note that the given depth must coincide with a JSON object (dictionary) in the payload. A depth of `0` will yield the previous functionality.

* Metadata instances will also no longer instantiate their own targets when their `target` property is accessed. This functionality has been removed as it served no real purpose and was more gimicky than useful given that you still had to tell it what its `targetClass` was anyway and therefore offered little functional difference over just instantiating it yourself and loading it normally. `targetClass` (renamed `nativeClass`) is now completely optional, and Presto will just instantiate an array or dictionary as determined by the payload.

#### 2015-09-03
* Renamed `load` to `reload` to better capture what this method represents. This method can be called at any time to reload an object on demand, whereas the naming `load` implies that it only should be called once. Since calling `reload` is not explicitly necessary the first time you use an object, it tends to be used exclusively for explicit reloading anyway. `loadFrom:` was also renamed to `loadWith:`.
