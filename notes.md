Záznam o pozorování foreign_keys.

PRAGMA foreign_keys = ON;

Přepínač platí jen pro aktuální spojení. Po .quit a novém spuštění je zase 0. Pro testera to znamená, že databáze sama nemusí hlídat integritu, a test, který vypadá zeleně, může jen běžet na spojení s vypnutou kontrolou.


Stav tabulky	COUNT(*)	GROUP BY ... HAVING
2× ORD-1001	2	řádek ORD-1001 / 2
prázdná (po DELETE)	řádek s hodnotou 0	nic
1× ORD-1001 (po smazání id = 2)	1	nic

dotaz, který umí selhat

Existují dva styly SQL kontroly:

“spočítej”: SELECT COUNT(*) ... a porovnej s očekáváním.
“najdi porušení”: dotaz vrací řádky, které nemají existovat. Prázdný výsledek = OK.

SELECT order_ref, COUNT(*) AS cnt
FROM payments
GROUP BY order_ref
HAVING COUNT(*) > 1;

### Co screenshot dokazuje

| Stav tabulky | `COUNT(*)` | `GROUP BY ... HAVING` |
| :--- | :--- | :--- |
| 2× `ORD-1001` | `2` | řádek `ORD-1001` / `2` |
| prázdná (po `DELETE`) | řádek s hodnotou `0` | **nic** |
| 1× `ORD-1001` (po smazání `id = 2`) | `1` | **nic** |

Slabina druhého stylu je stejná jako u falešně zelených testů z Vacation API: prázdný výsledek znamená “OK” i tehdy, když se nezapsalo vůbec nic.

SELECT order_ref, COUNT(*) AS cnt
FROM payments
WHERE order_ref = 'ORD-1001'
GROUP BY order_ref
HAVING COUNT(*) > 1;

Při O, 1 záznamech nevrací nic, při 2 vrací 2.

---
DELETE FROM payments se po novém vložení znovu použilo id 1 a 2 (tabulka nemá AUTOINCREMENT). Tohle je zajímavý fakt pro testera, protože id nemusí být v čase jednoznačné. Zatím ho jen poznamenej jako [POZOROVÁNO] a rozvedeme to později.

---


