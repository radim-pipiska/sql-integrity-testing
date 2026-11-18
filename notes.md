Záznam o pozorování foreign_keys.

PRAGMA foreign_keys = ON;

Přepínač platí jen pro aktuální spojení. Po .quit a novém spuštění je zase 0. Pro testera to znamená, že databáze sama nemusí hlídat integritu, a test, který vypadá zeleně, může jen běžet na spojení s vypnutou kontrolou.
