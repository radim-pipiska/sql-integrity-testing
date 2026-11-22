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
-- Spuštění z příkazové řádky (cestu k programu upravit podle instalace), vždy ze složky s databází: sqlite3 test.db
.databases        -- první kontrola: ukáže plnou cestu k otevřenému souboru
.headers on
.mode column

SELECT sqlite_version();
.quit
```
* `[POZOROVÁNO]` Verze `3.54.1` (balíček sqlite-tools-win-x64-3540100).

### Trvalost dat a správný soubor
* `[POZOROVÁNO]` Data v `test.db` po `.quit` a novém spuštění zůstala (řádky s `id` 3 a 4).
* `[POZOROVÁNO]` `sqlite3.exe` spuštěný z jiné složky než ze složky repozitáře pracoval s jinou kopií `test.db`. Po zkopírování souboru do složky repozitáře odpovídal jeho obsah očekávanému stavu.
* `[HYPOTÉZA]` Dojem, že data zmizela, mohl vzniknout i omylem provedeným `DROP` (příkaz vyvolaný šipkou z historie). Neověřeno.
* `[POZOROVÁNO]` `.databases` ukáže plnou cestu otevřeného souboru (`main: C:\qa\sql-integrity-testing\db\test.db r/w`). Používat jako první kontrolu po spuštění.

```text
Connected to a transient in-memory database.
Use ".open FILENAME" to reopen on a persistent database.
```
* `[POZOROVÁNO]` Při spuštění `sqlite3.exe` bez názvu souboru se otevřela dočasná databáze v paměti (`memory->`). `.databases` vypsal `main: "" r/w` a `.tables` nevrátilo žádné tabulky (ani dříve vytvořenou `payments`).
* `[VÝKLAD]` Podle hlášky SQLite jde o dočasnou databázi. Zapisování do ní a ukončení relace jsem nezkoušel, takže „data zaniknou“ je zatím jen výklad hlášky. Testovací prostředí má cílit na souborovou DB a po startu to ověřit přes `.databases`.

### Cizí klíče ([`foreign_keys`](screenshots/Foreign_Key_switch_valid_only_for_the_current_connection.png))
```sql
PRAGMA foreign_keys;       -- výchozí stav 0
PRAGMA foreign_keys = ON;
PRAGMA foreign_keys;       -- po zapnutí 1
```
* `[POZOROVÁNO]` Výchozí hodnota `0`, po `= ON` hodnota `1`, po `.quit` a novém spuštění zase `0`.
* `[POZOROVÁNO]` Po restartu byl výpis v jiném formátu (rámečková tabulka), protože jsem nenastavil `.mode column`. Nastavení výpisu tedy také platí jen pro jedno spojení.
* `[HYPOTÉZA]` Test může být zelený jen proto, že běží na spojení s vypnutou kontrolou cizích klíčů.
* `[POZOROVÁNO]` V `payments` zatím žádný cizí klíč není. Sabotáž: tabulka s `FOREIGN KEY`, vložit osiřelý záznam při `foreign_keys` = 0 a = 1.

### Opakované `id` po smazání vs. `AUTOINCREMENT`
* `[POZOROVÁNO]` Tabulka s `id INTEGER PRIMARY KEY` (bez `AUTOINCREMENT`): po `DELETE FROM payments;` dostaly nově vložené řádky znovu `id` `1` a `2`.
* `[POZOROVÁNO]` Tabulka znovu vytvořená s `id INTEGER PRIMARY KEY AUTOINCREMENT`: vložené dva řádky (`id` 1, 2), `DELETE FROM payments;`, opětovné vložení dvou řádků. `SELECT * FROM payments;` ukázal `id` `3` a `4`.
* `[POZOROVÁNO]` Tabulka `payments` byla pro druhý pokus znovu vytvořena (`DROP` + `CREATE`), takže v databázi už není v původní podobě bez `AUTOINCREMENT`.
* Schéma `db/payments.sql` bez `AUTOINCREMENT` a s ním `db/payments_autoinc.sql`. S `UNIQUE` je ve schématu `db/schema_payments_unique.sql`.
* `[VÝKLAD]` V pozorovaném případě se `id` s `AUTOINCREMENT` nezopakovala. Test, který po úklidu hledá záznam podle `id`, může u tabulky bez `AUTOINCREMENT` narazit na jiný, nově vytvořený řádek se stejným `id`.

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
* Aserce: `cnt = 1`. Z pozorovaných hodnot 0 / 1 / 2 / 3 je červená při 0 (ztracený zápis) i při 2 a 3 (duplicita).
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
* `[POZOROVÁNO]` 0 záznamů: `0 / 0`. 1 záznam: `1 / 0`. 2 záznamy: `2 / 1`. 3 záznamy: `3 / 2` (řádek z tabulky od AI se při spuštění potvrdil).
* `[VÝKLAD]` S filtrem `WHERE` je `COUNT(DISTINCT order_ref)` vždy 0 nebo 1, takže `pocet_duplicit` je při 0 i při 1 záznamu stejně `0`. Kdyby test hlídal jen tento sloupec, byl by při ztraceném zápisu falešně zelený. Zachraňuje ho první sloupec.

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

INSERT OR IGNORE INTO payments_u (order_ref, amount_cents, status) VALUES ('ORD-1001', 99900, 'PAID');
SELECT * FROM payments_u;
```

* `[POZOROVÁNO]` Druhý běžný `INSERT` se stejným `order_ref` selhal chybou (viz sekce 6) a `SELECT * FROM payments_u;` ukázal pouze 1 řádek (`1 | ORD-1001 | 15000 | PENDING`).
* `[POZOROVÁNO]` `INSERT OR IGNORE` se stejným `order_ref` nevypsal žádnou chybu. Po variantě s hodnotami `99900` a `PAID` ukázal `SELECT * FROM payments_u;` dál původní řádek beze změny (`1 | ORD-1001 | 15000 | PENDING`). Nové hodnoty se nezapsaly a původní řádek nepřepsaly.
* `[POZOROVÁNO]` Tabulka `payments` nemá `UNIQUE` na `order_ref` a databáze dva řádky se stejným klíčem přijala (na rozdíl od `payments_u`).
* `[VÝKLAD]` `OR IGNORE` je nástroj vývojáře: zbavuje chyb. Pro testera se hlasitý signál (chyba z databáze) změnil na tichý.
* `[HYPOTÉZA]` Po použití `OR IGNORE` v aplikaci už test nepozná z chyby, že se druhý zápis nepovedl, a navenek to může vypadat jako úspěch. Závisí na implementaci API.
* `[VÝKLAD]` Aserce `cnt = 1` by na `payments_u` po konfliktním zápisu prošla (v tabulce je 1 řádek), ale nezachytí, že hodnoty zůstaly původní. Test musí kontrolovat i `amount_cents` a `status`. Jaké hodnoty má očekávat, určuje specifikace, ne pozorované chování databáze.
* `[POZOROVÁNO]` `SELECT COUNT(*) AS cnt FROM payments_u WHERE order_ref = 'ORD-1001';` po konfliktním zápisu vrátil `1`. Aserce `cnt = 1` tedy prošla, přestože se nové hodnoty (`99900`, `PAID`) zahodily.

---

## 5. Otázky na analytika

* `[OTÁZKA NA ANALYTIKA]` Je `order_ref` obchodní klíč, který musí být unikátní?
* `[OTÁZKA NA ANALYTIKA]` Má opakované stejné `POST` vytvořit jeden záznam (idempotence), nebo vrátit chybu? Očekávání `cnt = 1` je zatím moje domněnka.
* `[OTÁZKA NA ANALYTIKA]` Co se má stát, když přijde druhý požadavek se stejným klíčem, ale jinou částkou nebo stavem: odmítnout, přepsat záznam, nebo vrátit původní? Podle toho test očekává buď původní, nebo nové hodnoty.
* `[OTÁZKA NA ANALYTIKA]` Má databáze `UNIQUE` na `order_ref`, nebo duplicitu hlídá jen aplikace?

---

## 6. Chybové hlášky (SQLite)

* Hláška pro [`HAVING COUNT(*) => 1;`](screenshots/HAVING_COUNT_Syntax_Error.png):
```text
Parse error near line 22: near ">": syntax error
   = 'ORD-1001' GROUP BY order_ref HAVING COUNT(*) => 1;
                                      error here ---^
```
* Hláška při porušení unikátního klíče v `payments_u` (zkopírováno z výstupu):
```text
Error near line 14: UNIQUE constraint failed: payments_u.order_ref
```

---

## 7. Cizí klíče (`FOREIGN KEY`) a osiřelé záznamy

Testovací schéma pro ověření referenční integrity (tabulka `order_items` odkazuje na `orders(id)`):

```sql
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;

CREATE TABLE orders (
  id        INTEGER PRIMARY KEY,
  order_ref TEXT NOT NULL UNIQUE
);

CREATE TABLE order_items (
  id       INTEGER PRIMARY KEY,
  order_id INTEGER NOT NULL REFERENCES orders(id),
  sku      TEXT NOT NULL
);

INSERT INTO orders (id, order_ref) VALUES (1, 'ORD-1001');
```

### Dotaz na hledání osiřelých záznamů („najdi porušení“)
```sql
SELECT i.id, i.order_id
FROM order_items i
LEFT JOIN orders o ON o.id = i.order_id
WHERE o.id IS NULL;
```

### Pozorované chování podle stavu `PRAGMA foreign_keys`

| Stav `foreign_keys` | Pokus o `INSERT` osiřelého záznamu | Výsledek `INSERT` | Výsledek dotazu na osiřelé záznamy (`LEFT JOIN ... IS NULL`) | Výsledek `PRAGMA foreign_key_check;` |
| :--- | :--- | :--- | :--- | :--- |
| **`0` (výchozí / OFF)** | `INSERT INTO order_items (order_id, sku) VALUES (999, 'SKU-1');` | **Prošel bez chyby** (záznam `id: 1, order_id: 999` se uložil do tabulky) | Vrátil `1` řádek (`1 \| 999`) | *(spuštěno až po zapnutí, ale detekuje tento řádek)* |
| **`1` (zapnuto / ON)** | `INSERT INTO order_items (order_id, sku) VALUES (998, 'SKU-2');` | **Selhal chybou** (záznam se neuložil) | Stále vrací dříve vložený řádek `1 \| 999` (zapnutí kontroly staré chyby neopraví) | Vrátil řádek: `order_items \| 1 \| orders \| 0` |

### Doslovné chybové hlášky (SQLite)
* Pokus o vložení neexistujícího `order_id` při `PRAGMA foreign_keys = ON`:
```text
Error near line 11: FOREIGN KEY constraint failed
```
* Chybné zavolání `foreign_key_check` bez klíčového slova `PRAGMA`:
```text
Parse error near line 13: near "foreign_key_check": syntax error
  foreign_key_check;
  ^--- error here
```

### Poznatky a využití v QA testech
* `[POZOROVÁNO]` Definice `REFERENCES orders(id)` v `CREATE TABLE` sama o sobě nezabrání vzniku osiřelých záznamů, dokud není na daném připojení explicitně zapnuto `PRAGMA foreign_keys = ON;`.
* `[POZOROVÁNO]` Zapnutí `PRAGMA foreign_keys = ON` chrání databázi pouze pro budoucí operace, ale historické sirotky (vložené v době, kdy byla kontrola vypnutá) nesmaže ani neopraví.
* `[VÝKLAD]` **Jak použít `PRAGMA foreign_key_check;` v testech:** Příkaz proskenuje uložená data proti definicím cizích klíčů a vypíše všechna porušení (tabulku, `rowid` vadného záznamu, cílovou rodičovskou tabulku a index klíče `fkid`). V testování (např. po migraci dat nebo po dávkovém importu, kdy bývá kontrola klíčů dočasně vypnutá) slouží jako rychlý auditní test: **prázdný výsledek = PASS (integrita v pořádku), jakýkoliv vrácený řádek = FAIL (v databázi jsou osiřelá data)**.
