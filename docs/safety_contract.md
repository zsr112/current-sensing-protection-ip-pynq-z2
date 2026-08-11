# Safety Contract

The production artifact uses `SAFE_INERT`: the digital source valid input is held inactive until Stage3 supplies an approved source integration. A live fault cannot be cleared into an unsafe release. Recovery is disable, clear-only, verify, then a separate enable action.

This prototype is not a certified safety product and does not authorize connection to a gate driver, motor, load, or power stage.
