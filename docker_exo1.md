# Quête 1 : Découverte Docker & PostgreSQL

## Résumé des actions effectuées

* Lancement d'un conteneur en tâche de fond nommé `demo-db` via l'image `postgres:16-alpine`.

* Connexion au client SQL interactif du conteneur (`psql`).

* Initialisation d'une table `products` avec ses colonnes correspondantes.

* Insertion d'une ligne de test : le produit `Sticker Démo` au prix de `150` centimes.

* Vérification des relations et du contenu via des requêtes SQL.

## Résultat de la commande \dt

```text
         List of relations
 Schema |   Name   | Type  | Owner 
--------+----------+-------+-------
 public | products | table | demo
(1 row)
```

## Résultat de la requête SELECT * FROM products;

```text
 id |     name     | price_cents 
----+--------------+-------------
  1 | Sticker Démo |         150
(1 row)
```

## Logs du conteneur PostgreSQL

*Affichage des dernières lignes d'activité générées par le serveur :*

```text
2026-10-06 12:52:42.214 UTC [1] LOG:  database system is ready to accept connections
2026-10-06 12:57:42.282 UTC [55] LOG:  checkpoint starting: time
2026-10-06 12:57:51.708 UTC [55] LOG:  checkpoint complete: wrote 96 buffers (0.6%); 0 WAL file(s) added, 0 removed, 0 recycled; write=9.347 s, sync=0.044 s, total=9.427 s; sync files=52, longest=0.010 s, average=0.001 s; distance=419 kB, estimate=419 kB; lsn=0/198EC18, redo lsn=0/198EBE0
```