SELECT COUNT(*) AS pocet_vyskytu
FROM payments
WHERE order_ref = 'ORD-1001';

Závěrečné řešení
SELECT COUNT(*) ... WHERE order_ref = 'ORD-1001' je správně. Hodnoty 2, 0, 2, 1 jsi už viděl na svých dřívějších screenshotech a to je jeho pozorované chování. Test:

- očekává přesně 1,
- je červený při 0 (zápis se ztratil) i při 2+ (duplicita),
- a nepotřebuje GROUP BY, HAVING ani DISTINCT.

Pozor na poznámku “bez WHERE”: bez filtru by COUNT(*) počítal řádky všech objednávek a rozbil by test, jakmile v tabulce bude jiný klíč.
