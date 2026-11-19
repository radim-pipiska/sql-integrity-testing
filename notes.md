# Poznámky z testování databází (SQLite)

## 1. Co ověřuje test v databázi vs. aserce na odpověď
* **Aserce na odpověď** ověřuje, co služba tvrdí (např. status `201`, tělo odpovědi, hlavičky).
* **Test v databázi** ověřuje, co se skutečně stalo (kolik záznamů vzniklo, s jakými hodnotami a v jakém stavu).
* *Poznámka z praxe:* Status `202 Accepted` znamená jen „přijato“ a u Vacation API vracel `200` i pro záznam uložený pod doslovným textem `{{PersonId}}`. Odpověď byla v pořádku, ale stav v databázi ne.

---

## 2. Chování databáze a prostředí (SQLite)

### Spuštění a nastavení výpisu
```sql
-- Spuštění z příkazové řádky: C:\sqlite\sqlite3.exe test.db
.headers on
.mode column

SELECT sqlite_version();
.quit
```

### Kontrola cizích klíčů (`foreign_keys`)
```sql
PRAGMA foreign_keys;       -- Výchozí stav je 0 (vypnuto)
PRAGMA foreign_keys = ON;  -- Zapnutí kontroly
```
* **[POZOROVÁNO]:** Přepínač platí jen pro aktuální spojení. Po `.quit` a novém spuštění je zase `0`. Pro testera to znamená, že databáze sama nemusí hlídat integritu, a test, který vypadá zeleně, může jen běžet na spojení s vypnutou kontrolou.

### Recyklace ID po smazání dat
* **[POZOROVÁNO]:** Po `DELETE FROM payments` se při novém vložení znovu použila `id` 1 a 2 (tabulka nemá `AUTOINCREMENT`). Pro testera je to důležitý fakt, protože `id` nemusí být v čase jednoznačné.

---

## 3. Dva styly SQL kontroly v testech
1. **„Spočítej“:** `SELECT COUNT(*) ...` a výsledek porovnej s očekáváním.
2. **„Najdi porušení“:** Dotaz vrací řádky, které nemají existovat. Prázdný výsledek = OK.

### Zkoumané dotazy

#### A) Styl „najdi porušení“ (`GROUP BY ... HAVING`)
```sql
SELECT order_ref, COUNT(*) AS cnt
FROM payments
GROUP BY order_ref
HAVING COUNT(*) > 1;
```
* **Slabina:** Stejná jako u falešně zelených testů z Vacation API – prázdný výsledek znamená „OK“ i tehdy, když se do databáze nezapsalo vůbec nic.
* **Pokusy o úpravu:**
  * Přidání `WHERE order_ref = 'ORD-1001'` problém nevyřešilo (při 0 a 1 záznamu nevrací nic, při 2 vrací `2` `[POZOROVÁNO]`).
  * Použití `HAVING COUNT(*) <> 0 OR COUNT(*) > 1` rozlišuje 0 od 1 (vrací `ORD-1001 / 1` a `ORD-1001 / 2`, při prázdné tabulce nic), ale výsledek se musí interpretovat – nejde o přímý pass/fail dotaz.

#### B) Složitější dotaz od AI (`DISTINCT`) `/AI`
```sql
SELECT 
    COUNT(*) AS celkem_radku,
    COUNT(*) - COUNT(DISTINCT order_ref) AS pocet_duplicit
FROM payments;
```
* **Zajímavý nález (skrytá díra):** Sloupec `pocet_duplicit` vrací při 0 záznamech `0` a při 1 záznamu také `0`. S filtrem `WHERE order_ref = 'ORD-1001'` je `COUNT(DISTINCT order_ref)` vždy 0 nebo 1, takže `pocet_duplicit` jen kopíruje `celkem_radku - 1` a při nule se vynuluje. Kdyby test hlídal jen tento sloupec, byl by falešně zelený (zachraňuje ho jen první sloupec).
* **[POZOROVÁNO]:** `(0/0, 1/0)`, při 2 záznamech `(2/1)`. Řádek pro 3× `ORD-1001` v tabulce od AI je `[AI, neověřeno]`.
* **Lekce:** AI dala složitější řešení, než bylo potřeba, a to mělo skrytou slabinu. Nejlepší test je ten nejjednodušší, který umí selhat.

#### C) Závěrečné řešení (`COUNT(*)`)
```sql
SELECT COUNT(*) AS pocet_vyskytu
FROM payments
WHERE order_ref = 'ORD-1001';
```
* **Proč je to správně:**
  * Test očekává přesně `1` (`cnt = 1`).
  * Je červený při `0` (zápis se ztratil) i při `2+` (duplicita).
  * Nepotřebuje `GROUP BY`, `HAVING` ani `DISTINCT`.
* **Pozor na filtr `WHERE`:** Bez podmínky `WHERE` by `COUNT(*)` počítal řádky všech objednávek a rozbil by test, jakmile by v tabulce přibyl jiný klíč.

---

## 4. Přehledové tabulky chování dotazů

### Původní srovnání (`COUNT(*)` vs. `GROUP BY ... HAVING`)

| Stav tabulky | `COUNT(*)` | `GROUP BY ... HAVING` |
| :--- | :--- | :--- |
| 2× `ORD-1001` | `2` | řádek `ORD-1001` / `2` |
| prázdná (po `DELETE`) | řádek s hodnotou `0` | **nic** |
| 1× `ORD-1001` (po smazání `id = 2`) | `1` | **nic** |

### Kompletní matice stavů 0 / 1 / 2 pro všechny tři dotazy

| Stav tabulky (`ORD-1001`) | `COUNT(*)` (s `WHERE`) | `GROUP BY ... HAVING > 1` | `DISTINCT` (`celkem` / `duplicity`) `/AI` |
| :--- | :--- | :--- | :--- |
| **0 záznamů** (prázdná) | `0` | *(nic / prázdný výsledek)* | `0` / `0` *(falešně zelené pro 2. sloupec)* |
| **1 záznam** (očekávaný stav) | `1` | *(nic / prázdný výsledek)* | `1` / `0` *(falešně zelené pro 2. sloupec)* |
| **2 záznamy** (duplicita) | `2` | `ORD-1001` \| `2` | `2` / `1` |

---

## 5. Zaznamenané chyby syntaxe (SQLite)
* **Chybný operátor `=>` místo `>=`:**
  ```text
  Parse error near line 153: near ">": syntax error
    FROM payments GROUP BY order_ref HAVING COUNT(*) => 0;
                                        error here ---^
  ```
* **Překlep `form` místo `FROM`:**
  ```text
  near "form": syntax error
  ```
