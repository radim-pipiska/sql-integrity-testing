CREATE TEMP TABLE parents (k INTEGER);
CREATE TEMP TABLE children (pk INTEGER);
INSERT INTO parents VALUES (1), (NULL);
INSERT INTO children VALUES (1), (999);

SELECT COUNT(*) AS not_in     FROM children WHERE pk NOT IN (SELECT k FROM parents);
SELECT COUNT(*) AS left_join  FROM children c LEFT JOIN parents p ON p.k = c.pk WHERE p.k IS NULL;
SELECT COUNT(*) AS not_exists FROM children c WHERE NOT EXISTS (SELECT 1 FROM parents p WHERE p.k = c.pk);
