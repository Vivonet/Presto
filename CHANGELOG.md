#Breaking Changes

* **2015-09-03** Renamed `load` to `reload` to better capture what this method represents. This method can be called at any time to reload an object on demand, whereas the naming `load` implies that it only should be called once. Since calling `reload` is not explicitly necessary the first time you use an object, it tends to be used exclusively for explicit reloading anyway. `loadFrom:` was also renamed to `loadWith:`.
