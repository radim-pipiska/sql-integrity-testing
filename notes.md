# Poznámky: testování databází (SQLite)

Stav k 26. 11. 2026. Data v tabulkách `payments`, `payments_u`, `orders` a `order_items` jsou **simulovaná ručními `INSERT`y**, žádné reálné API se tu nevolá. `[POZOROVÁNO]` se proto týká chování SQLite a mých dotazů, ne chování nějaké služby.

**Značky:** `[POZOROVÁNO]` = viděl jsem na vlastním výstupu · `[VÝKLAD]` = můj závěr z pozorování · `[HYPOTÉZA]` / `[OVĚŘIT]` = zatím nepodloženo · `[OTÁZKA NA ANALYTIKA]` · `/AI` = výstup AI, platí až po ověření spuštěním

*`[OVĚŘIT]` Falešně zelený = test prošel, přestože vada existuje (v terminologii ISTQB false-negative). Tento termín používám místo nejednoznačného 'falešně pozitivní'.*

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
* `[POZOROVÁNO]` `.databases` ukáže plnou cestu otevřeného souboru (`...\db\test.db`). Používat jako první kontrolu po spuštění.

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
* `[POZOROVÁNO]` V `payments` žádný cizí klíč není. Sabotáž s cizím klíčem je v sekci 7.
* `[VÝKLAD]` Při `foreign_keys = 0` databáze osiřelý záznam přijala (sekce 7). Test, který se na cizí klíč spoléhá jako na ochranu, proto musí ověřit, že je kontrola na daném spojení zapnutá.

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

Schéma (`db/schema_fk.sql`): tabulka `order_items` odkazuje na `orders(id)`.

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

### Postup v jedné relaci ([pozorované výsledky](screenshots/Foreign_keys_and_orphaned_records.png))

| Krok | `foreign_keys` | Příkaz | Pozorovaný výsledek |
| :--- | :--- | :--- | :--- |
| 1 | `0` | `PRAGMA foreign_keys;` | `0` |
| 2 | `0` | `INSERT INTO order_items (order_id, sku) VALUES (999, 'SKU-1');` | bez chyby; `SELECT * FROM order_items;` ukázal `1 \| 999 \| SKU-1` |
| 3 | `0` | dotaz na osiřelé záznamy | `1 \| 999` |
| 4 | `1` (po `= ON`) | `INSERT INTO order_items (order_id, sku) VALUES (998, 'SKU-2');` | chyba `FOREIGN KEY constraint failed` |
| 5 | `1` | `SELECT * FROM order_items;` | stále jen `1 \| 999 \| SKU-1` (998 se neuložil, 999 nezmizel) |
| 6 | `1` | `PRAGMA foreign_key_check;` | `order_items \| 1 \| orders \| 0` |
| – | `1` | dotaz na osiřelé záznamy po zapnutí | `[OVĚŘIT]` nespuštěno (v kroku 5 jen `SELECT *`) |
| 7 | nová relace (`foreign_keys` nevypsáno, dříve vždy `0`) | `PRAGMA foreign_key_check;` s osiřelým řádkem | `order_items \| 1 \| orders \| 0` |
| 8 | stejná | po `DELETE FROM order_items WHERE order_id = 999;` | žádné řádky (v režimu bez .mode column jen hlavička) |
| 9 | stejná | po `DELETE FROM order_items;`, `SELECT COUNT(*) FROM order_items;` | kontrola bez řádků, `COUNT(*) = 0` |

### Doslovné hlášky (SQLite)
```text
Error near line 11: FOREIGN KEY constraint failed
```
```text
Parse error near line 13: near "foreign_key_check": syntax error
  foreign_key_check;
  ^--- error here
```
* `[POZOROVÁNO]` Druhá hláška vznikla zadáním `foreign_key_check;` bez slova `PRAGMA`. Správně je `PRAGMA foreign_key_check;`.

### Poznatky
* `[POZOROVÁNO]` Definice `REFERENCES orders(id)` sama osiřelý záznam nezabrání: při `foreign_keys = 0` databáze `INSERT` s `order_id = 999` přijala (kroky 2 a 3).
* `[POZOROVÁNO]` Po zapnutí `foreign_keys = ON` selhal nový `INSERT` s neexistujícím `order_id` a dříve vložený osiřelý řádek zůstal (kroky 4 a 5). Zapnutí kontroly tedy starý osiřelý řádek neopravilo ani nesmazalo.
* `[POZOROVÁNO]` `PRAGMA foreign_key_check;` vrátil sloupce `table`, `rowid`, `parent`, `fkid` a řádek `order_items | 1 | orders | 0`.
* `[VÝKLAD]` Zapnutá kontrola chrání nové `INSERT`y. Chování při `UPDATE` a `DELETE` jsem nezkoušel: `[OVĚŘIT]`.
* `[VÝKLAD]` Prázdný výsledek dotazu na osiřelé záznamy i `PRAGMA foreign_key_check;` by byl falešně zelený, kdyby se do tabulek nezapsalo nic. Stejná slabina jako u kontroly duplicit (sekce 3). Kontrolu je třeba doplnit o očekávaný počet řádků (např. `SELECT COUNT(*) FROM order_items WHERE order_id = 1;`).
* `[HYPOTÉZA]` Použití `PRAGMA foreign_key_check;` jako auditního kroku po migraci nebo dávkovém importu (kdy bývá kontrola dočasně vypnutá). Nepozorováno, zatím jen obecná úvaha.
* `[POZOROVÁNO]` `PRAGMA foreign_key_check;` osiřelý řádek našel i bez zapnutého `foreign_keys = ON`.
* `[POZOROVÁNO]` Výsledek kontroly se mění podle aktuálních dat, neukládá se.
* `[VÝKLAD]` Kontrola nad prázdnou tabulkou je prázdná, stejně jako nad tisíci platnými řádky. Aby test něco dokazoval, musí ověřit i očekávaný počet řádků.
* `[HYPOTÉZA]` Prázdný výsledek se vypisuje různě podle `.mode`. `[OVĚŘIT]`.

---

## 8. [Jedna kontrola:](screenshots/Single_Check_Item_Count_and_Orphaned_Records.png) počet položek a osiřelé záznamy

Kontrola vždy vrátí jeden řádek se dvěma čísly. Očekávání (`1` položka, `0` osiřelých) pochází ze vstupu testu: v simulaci vkládám jednu položku pro objednávku 1.

```sql
SELECT
  (SELECT COUNT(*) FROM order_items WHERE order_id = 1) AS order_1_items,
  (SELECT COUNT(*) FROM order_items WHERE order_id NOT IN (SELECT id FROM orders)) AS orphaned_items;
```

| Stav `order_items` | Pozorovaný výsledek | Pass/fail při očekávání `1` a `0` |
| :--- | :--- | :--- |
| prázdná | `0 \| 0` | FAIL (chybí položka) |
| 1 platná položka (`order_id = 1`) | `1 \| 0` | PASS |
| 1 osiřelá položka (`order_id = 999`) | `0 \| 1` | FAIL |

* `[POZOROVÁNO]` `foreign_keys` bylo před pokusem `0`.
* `[POZOROVÁNO]` `SELECT COUNT(*) FROM pragma_foreign_key_check;` se dá zavolat. První spuštění vrátilo `0` bez vypsaného stavu tabulky, takže samotná nula nic nedokazuje. Detekce s osiřelým řádkem je v odrážce níže.
* `[VÝKLAD]` Dotaz s agregací bez `GROUP BY` vrací vždy jeden řádek, takže se „nic“ liší od „v pořádku“.
* `[POZOROVÁNO]` `SELECT typeof(999 NOT IN (1, NULL));` vrátilo `null`: výraz se vyhodnotí jako „neznámo“, ne jako pravda.
* `[POZOROVÁNO]` S osiřelým řádkem `20 | 999 | SKU-ORPHAN` a `foreign_keys = 0` vrátil `SELECT COUNT(*) FROM pragma_foreign_key_check;` hodnotu `1` a `LEFT JOIN` dotaz řádek `20 | 999`.
* `[POZOROVÁNO]` Na dočasných tabulkách (`parents` s hodnotami `1` a `NULL`, `children` s `1` a `999`) našly osiřelý řádek `999` dotazy s `LEFT JOIN` (`1`) i `NOT EXISTS` (`1`), `NOT IN` ne (`0`). Při `NULL` v rodičovském sloupci je `NOT IN` falešně zelený. V `db/schema_fk.sql` k tomu nedojde, protože `orders.id` je `INTEGER PRIMARY KEY`.

---

## 9. Tři alternativní dotazy: `NOT EXISTS`, `/AI` 1, `/AI` 2

Cíl: zjistit, jestli stejná kontrola (počet položek objednávky 1 a počet osiřelých) dává ve stejných stavech stejná čísla, když ji zapíšu čtyřmi způsoby.

Prostředí: SQLite 3.54.1, schéma `db/schema_fk.sql`, v `orders` jen `id = 1`, `foreign_keys = 0` (výchozí, vypsáno jen u AI 1). Soubory: `checks/order_items_integrity.sql` (`NOT EXISTS`), `[DOPLNIT RUČNĚ: cesta k alt_ai_1.sql a alt_ai_2.sql]`. AI 1 jsem spustil vložením textu do terminálu, `NOT EXISTS` a AI 2 přes `.read`.

Stavy: prázdná `order_items`; 1 platná položka (`order_id = 1`); 1 osiřelá položka (`order_id = 999`).

| Stav | `NOT IN` (původní) | `NOT EXISTS` | AI 1 | AI 2 |
| :--- | :--- | :--- | :--- | :--- |
| prázdná | `0 / 0` | `0 / 0` | `0 / 0` | `0 / 0` |
| 1 platná | `1 / 0` | `1 / 0` | `1 / 0` | `1 / 0` |
| 1 osiřelá | `0 / 1` | `0 / 1` | `0 / 1` | `0 / 1` |

(Formát `order_1_items / orphaned_items`.)

* `[POZOROVÁNO]` Všechny čtyři zápisy daly ve všech třech stavech stejná čísla. Moje tipy před spuštěním byly stejné.
* `[POZOROVÁNO]` Oba dotazy od AI byly v těchto třech stavech správné. Teze „AI dotaz bude horší“ se tímto pokusem nepotvrdila.
* `[VÝKLAD]` Past `NOT IN` s `NULL` (sekce 8) se zde neprojevila, protože `orders.id` je `INTEGER PRIMARY KEY` a `NULL` mít nemůže. Shoda ve třech stavech nedokazuje, že jsou dotazy rovnocenné ve všech případech.

### [`NOT EXISTS`](screenshots/Order_items_integrity_sql.png)

```sql
SELECT
  (SELECT COUNT(*) FROM order_items WHERE order_id = 1) AS order_1_items,
  (SELECT COUNT(*)
     FROM order_items i
    WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.id = i.order_id)) AS orphaned_items;
```
* `[POZOROVÁNO]` Na prázdné tabulce vrátil `0 / 0`.
* `[VÝKLAD]` `NOT EXISTS` nemá past s `NULL` jako `NOT IN`. `[OVĚŘIT]` na dočasných tabulkách, kde rodičovský sloupec obsahuje `NULL`.
* `[HYPOTÉZA]` Dva poddotazy znamenají dva průchody `order_items`. Výkon jsem neměřil. `[OVĚŘIT]` přes `EXPLAIN QUERY PLAN`, na malých datech to ale nemá význam.

### [AI 1](screenshots/Single_Check_Item_Count_and_Orphaned_Records_AI_SQL_1.png) (`LEFT JOIN` + podmíněné součty) `/AI`

```sql
SELECT
  COALESCE(SUM(CASE WHEN oi.order_id = 1 THEN 1 ELSE 0 END), 0) AS order_1_items,
  COALESCE(SUM(CASE WHEN o.id IS NULL THEN 1 ELSE 0 END), 0) AS orphaned_items
FROM order_items oi
LEFT JOIN orders o ON oi.order_id = o.id;
```
* `[POZOROVÁNO]` Na prázdné tabulce vrátil `0 / 0`.
* `[VÝKLAD]` `COALESCE` má smysl, protože `SUM` nad prázdnou množinou vrací `NULL`. `[OVĚŘIT]` sabotáží: spustit bez `COALESCE` na prázdné tabulce.
* `[HYPOTÉZA]` Kdyby rodičovský klíč v `orders` nebyl unikátní, `LEFT JOIN` by mohl řádky zdvojit a čísla zkreslit. `[OVĚŘIT]`.

### [AI 2](screenshots/Single_Check_Item_Count_and_Orphaned_Records_AI_SQL_2.png) (CTE + podmíněné součty) `/AI`

```sql
WITH item_integrity_flags AS (
  SELECT
    oi.id AS item_id,
    oi.order_id,
    CASE 
      WHEN oi.order_id = 1 THEN 1 
      ELSE 0 
    END AS is_target_order,
    CASE 
      WHEN o.id IS NULL THEN 1 
      ELSE 0 
    END AS is_orphaned
  FROM order_items oi
  LEFT JOIN orders o 
    ON oi.order_id = o.id
),
aggregated_metrics AS (
  SELECT
    SUM(is_target_order) AS raw_order_1_count,
    SUM(is_orphaned) AS raw_orphaned_count
  FROM item_integrity_flags
)
SELECT
  COALESCE(raw_order_1_count, 0) AS order_1_items,
  COALESCE(raw_orphaned_count, 0) AS orphaned_items
FROM aggregated_metrics;
```
* `[POZOROVÁNO]` Přes `.read` vrátil ve třech stavech `0 / 0`, `1 / 0`, `0 / 1`.
* `[VÝKLAD]` Dělá stejnou práci jako AI 1, jen v delším zápisu. Pro tuto úlohu nic nepřidává. Výkonnostní rozdíl jsem neměřil.

### Závěr

Pro tuto úlohu je nejjednodušší varianta (`NOT EXISTS`) stejně spolehlivá jako obě od AI. Žádnou „doporučenou“ variantu zatím neurčuji: nejdřív ověřím `NULL` v rodičovském sloupci a neunikátní rodičovský klíč (`LEFT JOIN`).
