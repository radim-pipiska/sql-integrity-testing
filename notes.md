# Poznámky: testování databází (SQLite)

Stav k 21. 11. 2026. Data v tabulkách `payments` a `payments_u` jsou **simulovaná ručními `INSERT`y**, žádné reálné API se tu nevolá. `[POZOROVÁNO]` se proto týká chování SQLite a mých dotazů, ne chování nějaké služby.

**Značky:** `[POZOROVÁNO]` = viděl jsem na vlastním výstupu · `[VÝKLAD]` = můj závěr z pozorování · `[HYPOTÉZA]` / `[OVĚŘIT]` = zatím nepodloženo · `[OTÁZKA NA ANALYTIKA]` · `/AI` = výstup AI, platí až po ověření spuštěním

---

## 1. Odpověď API vs. stav v databázi

* **Aserce na odpověď** ověřuje, co služba tvrdí (status `201`, tělo, hlavičky).
* **Test v databázi** ověřuje, co se skutečně stalo (kolik záznamů vzniklo, s jakými hodnotami, v jakém stavu).
* Příklad z Vacation API (týdny 5–6): `[POZOROVÁNO]` API vrátilo `200` pro nerozbalenou proměnnou `{{PersonId}}` a zapsalo záznam pod tento doslovný text. Stav jsem viděl přes API, ne přímo v databázi (k databázi Vacation API nemám přístup).
  * `[OTÁZKA NA ANALYTIKA]` Má API přijmout libovolný text jako `PersonId`?
* Odlišný případ: `202 Accepted` znamená jen „přijato“, konečný stav se ověřuje následně (týdny 5–6).

---

## 2. Chování prostředí (SQLite)

```sql
-- Spuštění z příkazové řádky (cestu k programu upravit podle instalace): sqlite3 test.db
.headers on
.mode column

SELECT sqlite_version();
.quit
```
* `[POZOROVÁNO]` Verze `3.54.1` (balíček sqlite-tools-win-x64-3540100).

### Test trvalosti dat (paměťová vs. souborová DB)
```text
Connected to a transient in-memory database.
Use ".open FILENAME" to reopen on a persistent database.
```
* `[POZOROVÁNO]` Při spuštění `sqlite3.exe` bez parametru souboru se otevřela dočasná databáze v paměti (`memory->`). Příkaz `.databases` vypsal `main: "" r/w` a `.tables` nevrátilo žádné tabulky (ani dříve vytvořenou `payments`).
* `[VÝKLAD]` Data zapsaná bez otevření konkrétního souboru (např. `test.db`) se neukládají na disk a po ukončení relace zanikají. Testovací prostředí musí explicitně cílit na souborovou DB, jinak se data ztratí.

### Cizí klíče ([`foreign_keys`](screenshots/Foreign_Key_switch_valid_only_for_the_current_connection.png))
```sql
PRAGMA foreign_keys;       -- výchozí stav 0
PRAGMA foreign_keys = ON;
PRAGMA foreign_keys;       -- po zapnutí 1
```
* `[POZOROVÁNO]` Výchozí hodnota `0`, po `= ON` hodnota `1`, po `.quit` a novém spuštění zase `0`.
* `[POZOROVÁNO]` Po restartu byl výpis v jiném formátu (rámečková tabulka), protože jsem nenastavil `.mode column`. Nastavení výpisu tedy také platí jen pro jedno spojení.
* `[HYPOTÉZA]` Test může být zelený jen proto, že běží na spojení s vypnutou kontrolou cizích klíčů.
* `[OVĚŘIT]` V `payments` zatím žádný cizí klíč není. Sabotáž: tabulka s `FOREIGN KEY`, vložit osiřelý záznam při `foreign_keys` = 0 a = 1.

### Opakované `id` po smazání vs. `AUTOINCREMENT`
* `[POZOROVÁNO]` U tabulky definované s `id INTEGER PRIMARY KEY` (bez `AUTOINCREMENT`) dostaly nově vložené řádky po `DELETE FROM payments;` znovu `id` `1` a `2`.
* `[POZOROVÁNO]` Po úpravě definice na `id INTEGER PRIMARY KEY AUTOINCREMENT` a následném `DELETE FROM payments;` ověřeno dotazem `SELECT * FROM payments;`, že nově vložené řádky dostaly navazující `id` `3` a `4` (místo recyklovaných `1` a `2`).
* `[VÝKLAD]` Test, který po úklidu hledá záznam podle `id`, může u tabulky bez `AUTOINCREMENT` narazit na jiný, nově vytvořený řádek se stejným `id`. S `AUTOINCREMENT` se `id` nezopakuje.

---

## 3. Kontrola duplicity: čtyři dotazy a jejich chování

Dva styly SQL kontroly:
1. **„Spočítej“:** `SELECT COUNT(*) ...` a porovnat s očekáváním.
2. **„Najdi porušení“:** dotaz vrací řádky, které nemají existovat; prázdný výsledek = OK.

### [Dotaz 1:](screenshots/Duplicate_Check_with_COUNT.png) `COUNT(*)` (závěrečné řešení)
```sql
SELECT COUNT(*) AS cnt
FROM payments
WHERE order_ref = 'ORD-1001';
```
* Aserce: `cnt = 1`. Z pozorovaných hodnot 0 / 1 / 2 je červená při 0 (ztracený zápis) i při 2 (duplicita).
* Filtr `WHERE` je nutný: bez něj by dotaz počítal řádky všech objednávek.
* Alternativy aserce `cnt >= 1`, `cnt <> 0` (zelené při 2) a `cnt < 2` (zelená při 0) neumí zachytit obě chyby.

### [Dotaz 2:](screenshots/Duplicate_Check_with_WHERE.png) „najdi porušení“
```sql
SELECT order_ref, COUNT(*) AS cnt
FROM payments
WHERE order_ref = 'ORD-1001'
GROUP BY order_ref
HAVING COUNT(*) > 1;
```
* `[POZOROVÁNO]` Při 0 i 1 záznamu **žádný řádek**, při 2 záznamech řádek `ORD-1001 / 2`. Bez `WHERE` stejné chování.
* `[VÝKLAD]` Prázdný výsledek nerozliší „nic se nezapsalo“ od „je to v pořádku“. `GROUP BY` na prázdné množině nevytvoří žádnou skupinu, `HAVING` to nezmění.

### [Dotaz 3:](screenshots/Duplicate_Check_HAVING_COUNT.png) varianta s `HAVING`
```sql
SELECT order_ref, COUNT(*) AS cnt
FROM payments
GROUP BY order_ref
HAVING COUNT(*) <> 0 OR COUNT(*) > 1;
```
* `[POZOROVÁNO]` 0 záznamů: žádný řádek. 1 záznam: `ORD-1001 / 1`. 2 záznamy: `ORD-1001 / 2`.
* `[VÝKLAD]` Rozliší 0 od 1, ale výsledek se musí interpretovat, takže to není přímý pass/fail. Část `OR COUNT(*) > 1` je zbytečná.

### [Dotaz 4:](screenshots/Duplicate_Check_with_DISTINCT.png) `DISTINCT` `/AI`
```sql
SELECT
    COUNT(*) AS celkem_radku,
    COUNT(*) - COUNT(DISTINCT order_ref) AS pocet_duplicit
FROM payments
WHERE order_ref = 'ORD-1001';
```
* `[POZOROVÁNO]` 0 záznamů: `0 / 0`. 1 záznam: `1 / 0`. 2 záznamy: `2 / 1`.
* `[VÝKLAD]` S filtrem `WHERE` je `COUNT(DISTINCT order_ref)` vždy 0 nebo 1, takže `pocet_duplicit` je při 0 i při 1 záznamu stejně `0`. Kdyby test hlídal jen tento sloupec, byl by při ztraceném zápisu falešně zelený. Zachraňuje ho první sloupec.
* Řádek pro 3× `ORD-1001` v tabulce od AI: `[AI, pozorováno]`.

### Přehled (stavy tabulky pro `ORD-1001`)

| Stav | Dotaz 1 `COUNT(*)` | Dotaz 2 `HAVING > 1` | Dotaz 3 `HAVING <> 0 OR > 1` | Dotaz 4 `/AI` (celkem / duplicity) |
| :--- | :--- | :--- | :--- | :--- |
| 0 záznamů | řádek s hodnotou `0` | žádný řádek | žádný řádek | `0 / 0` |
| 1 záznam (očekáváno) | `1` | žádný řádek | `ORD-1001 / 1` | `1 / 0` |
| 2 záznamy (duplicita) | `2` | `ORD-1001 / 2` | `ORD-1001 / 2` | `2 / 1` |
| 3 záznamy | `3` | neověřeno | neověřeno | `3 / 2` |

**Lekce:** nejlepší test je ten nejjednodušší, který umí selhat. Dotaz od AI byl složitější, než bylo potřeba, a jeho druhý sloupec sám o sobě nestačí.

---

## 4. Omezení `UNIQUE` a tiché potlačení chyby (`OR IGNORE`)

```sql
DROP TABLE IF EXISTS payments_u;
CREATE TABLE payments_u (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  order_ref    TEXT    NOT NULL UNIQUE,
  amount_cents INTEGER NOT NULL,
  status       TEXT    NOT NULL
);

INSERT INTO payments_u (order_ref, amount_cents, status) VALUES ('ORD-1001', 15000, 'PENDING');
INSERT INTO payments_u (order_ref, amount_cents, status) VALUES ('ORD-1001', 15000, 'PENDING');
```

* `[POZOROVÁNO]` Druhý běžný `INSERT` se stejným `order_ref` selhal chybou (viz sekce 5) a dotaz `SELECT * FROM payments_u;` potvrdil, že v tabulce zůstal pouze 1 řádek (`1 | ORD-1001 | 15000 | PENDING`).
* `[POZOROVÁNO]` Po spuštění `INSERT OR IGNORE INTO payments_u (order_ref, amount_cents, status) VALUES ('ORD-1001', 99900, 'PAID');` SQLite nevypíše žádnou chybu. Dotaz `SELECT * FROM payments_u;` potvrdil, že v tabulce zůstal původní záznam beze změny (`1 | ORD-1001 | 15000 | PENDING`), nové hodnoty (`99900`, `PAID`) se nezapsaly ani nepřepsaly původní řádek.
* `[VÝKLAD]` `OR IGNORE` je nástroj vývojáře: zbavuje chyb a z pohledu kódu je pohodlný. Pro testera je to přesně obráceně, protože hlasitý signál (chyba z databáze) se změnil na tichý a duplicitní nebo konfliktní požadavek vypadá navenek jako úspěch.
* `[HYPOTÉZA]` Po použití `OR IGNORE` v aplikaci už test nepozná z chyby, že se druhý zápis nepovedl.

---

## 5. Otázky na analytika

* `[OTÁZKA NA ANALYTIKA]` Je `order_ref` obchodní klíč, který musí být unikátní?
* `[OTÁZKA NA ANALYTIKA]` Má opakované stejné `POST` vytvořit jeden záznam (idempotence), nebo vrátit chybu? Očekávání `cnt = 1` je zatím moje domněnka.
* `[POZOROVÁNO]` Tabulka `payments` nemá omezení `UNIQUE` na `order_ref`, takže databáze dva řádky se stejným klíčem přijala (na rozdíl od testovací tabulky `payments_u`).

---

## 6. Chybové hlášky (SQLite)

* Doslovná hláška pro [`HAVING COUNT(*) => 0;`](screenshots/HAVING_COUNT_Syntax_Error.png), zkopírovaná z terminálu (ne přepsaná).
* Doslovná hláška při porušení unikátního klíče v `payments_u` (zkopírováno z výstupu):
```text
Error near line 14: UNIQUE constraint failed: payments_u.order_ref
```
