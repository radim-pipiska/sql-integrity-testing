# sql-integrity-testing

Učební projekt o tom, jak ověřit **skutečný stav databáze** po integraci, a ne jen odpověď služby. Praktické pokusy v SQLite (příkazová řádka `sqlite3`, verze 3.54.1) s doslovnými výstupy, sabotážemi a rozlišením, co je pozorování a co jen hypotéza.

> **Důležité:** všechna data jsou **simulovaná ručními `INSERT`y**. Repozitář netestuje žádné reálné API ani produkční databázi. Pozorování se týká chování SQLite a mých dotazů, ne nějaké služby.

Stav k 21. 11. 2026, rozpracováno.

## Obsah

* [`notes.md`](notes.md): hlavní výstup. Pozorování, dotazy, tabulky chování a otázky na analytika.
* [`screenshots/`](screenshots/): výstupy z terminálu, na které se `notes.md` odkazuje.
* `db/`: `[DOPLNIT RUČNĚ: názvy souborů se schématy, např. payments bez AUTOINCREMENT, s AUTOINCREMENT, payments_u s UNIQUE]`

## Hlavní zjištění

1. **Odpověď vs. stav databáze.** Status `201` říká, co služba tvrdí. Teprve dotaz do databáze ukáže, co se stalo (počet záznamů, hodnoty, stav).
2. **Kontrola „prázdný výsledek = OK“ umí být falešně zelená.** Dotaz s `GROUP BY ... HAVING COUNT(*) > 1` nevrátí nic při 0 záznamech ani při 1. Nerozliší tedy „nic se nezapsalo“ od „je to v pořádku“.
3. **Nejjednodušší spolehlivá kontrola duplicity:** `SELECT COUNT(*) ... WHERE order_ref = '...'` s očekáváním přesně `1`. Je červená při 0 i při 2 a více.
4. **Složitější neznamená lepší.** Dotaz od AI s `COUNT(DISTINCT ...)` měl druhý sloupec, který je při 0 i při 1 záznamu stejný (`0`), a sám o sobě tedy nestačí.
5. **`UNIQUE` a `INSERT OR IGNORE`.** `UNIQUE` zabrání duplicitě, ale `OR IGNORE` chybu skryje. Počet řádků zůstane `1`, jenže nové hodnoty se tiše zahodí. Test proto musí ověřit i hodnoty, a očekávané hodnoty určuje specifikace.
6. **Prostředí může zkreslit výsledek.** `PRAGMA foreign_keys` je po každém spuštění `0`. Bez názvu souboru se otevře databáze v paměti. Po spuštění ze špatné složky jsem pracoval s jiným `test.db`. První kontrola je proto `.databases`.

## Jak pracuji

* Před každým spuštěním si zapíšu **tip**, co dotaz vrátí.
* Každý test musí umět **selhat**: vyrobím stav (0, 1, 2 a více záznamů) a ověřím, že je červený tam, kde má být.
* Značky v `notes.md`: `[POZOROVÁNO]`, `[VÝKLAD]`, `[HYPOTÉZA]`, `[OVĚŘIT]`, `[OTÁZKA NA ANALYTIKA]`, `/AI`.
* Výstupy AI označuji `/AI` a platí až po ověření spuštěním.
* Hlášky z terminálu kopíruji doslova, nepřepisuji je.

## Jak to vyzkoušet

1. Stáhněte nástroje SQLite (`sqlite-tools`) z [sqlite.org](https://www.sqlite.org/download.html).
2. V terminálu přejděte do složky `db/` a spusťte databázi se souborem: `sqlite3 test.db`.
3. Ověřte, kde jste: `.databases` (musí ukázat cestu k `test.db`).
4. Načtěte schéma: `.read [DOPLNIT RUČNĚ: název souboru]`.
5. Postupujte podle dotazů v `notes.md`.

## Plánováno

* cizí klíče: osiřelý záznam při `foreign_keys` = 0 a 1
* transakce (`BEGIN`, `COMMIT`, `ROLLBACK`) a úklid testovacích dat

## Licence

`[DOPLNIT RUČNĚ: licence, např. MIT]`
