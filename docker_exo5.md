# Quête 5 : Docker - Les volumes

## Résumé des actions effectuées

- Création du script `volumes_ethan_bermond.sh` permettant d'automatiser :
    - Le build de l'image `demo-api:1.0`.
    - La création du réseau `demo_net` et du volume nommé `demo_pgdata`.
    - Le lancement de `demo-db` (`postgres:16-alpine`) avec le volume monté sur `/var/lib/postgresql/data` et le script d'initialisation `db/init.sql` monté en lecture seule.
    - L'attente de disponibilité de PostgreSQL via `pg_isready`.
    - Le lancement de `demo-api` connecté à `demo-db` et l'ajout du produit « Casquette Démo » via `POST /products`.
    - La suppression (`docker rm -f demo-db`) puis la recréation du conteneur de base de données sur le même volume `demo_pgdata` pour prouver la persistance des données.

---

## 1. Script `volumes_ethan_bermond.sh`

```bash
#!/usr/bin/env bash
set -e

export MSYS_NO_PATHCONV=1

echo "=== 0. Nettoyage préventif ==="
docker rm -f demo-api demo-db 2>/dev/null || true
docker network rm demo_net 2>/dev/null || true

echo "=== 1. Build de l'image demo-api:1.0 ==="
docker build -t demo-api:1.0 ./api

echo "=== 2. Création du réseau et du volume nommé demo_pgdata ==="
docker network create demo_net
docker volume create demo_pgdata

echo "=== 3. Lancement du conteneur demo-db (postgres:16-alpine) ==="
docker run -d --name demo-db \
  --network demo_net \
  -v demo_pgdata:/var/lib/postgresql/data \
  -v "$(pwd)/db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro" \
  -e POSTGRES_USER=demo \
  -e POSTGRES_PASSWORD=demo \
  -e POSTGRES_DB=demo \
  postgres:16-alpine

echo "=== 4. Attente que la base de données soit prête ==="
until docker exec demo-db pg_isready -U demo -d demo; do
  echo "En attente de PostgreSQL..."
  sleep 1
done

echo "=== 5. Lancement de demo-api ==="
docker run -d --name demo-api \
  --network demo_net \
  -p 8080:3000 \
  -e PGHOST=demo-db \
  demo-api:1.0

sleep 2

echo "=== 6. Ajout du produit 'Casquette Démo' (POST /products) ==="
curl -s -X POST -H 'content-type: application/json' \
  -d '{"name":"Casquette Démo","price_cents":1200}' http://localhost:8080/products
echo ""

echo "--- Vérification AVANT suppression de demo-db (GET /products) ---"
curl -s http://localhost:8080/products
echo ""

echo "=== 7. Suppression et recréation de demo-db avec le même volume ==="
docker rm -f demo-db

docker run -d --name demo-db \
  --network demo_net \
  -v demo_pgdata:/var/lib/postgresql/data \
  -v "$(pwd)/db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro" \
  -e POSTGRES_USER=demo \
  -e POSTGRES_PASSWORD=demo \
  -e POSTGRES_DB=demo \
  postgres:16-alpine

echo "=== Attente du redémarrage de la base ==="
until docker exec demo-db pg_isready -U demo -d demo; do
  echo "En attente de PostgreSQL..."
  sleep 1
done

echo "=== Relance de demo-api ==="
docker rm -f demo-api
docker run -d --name demo-api \
  --network demo_net \
  -p 8080:3000 \
  -e PGHOST=demo-db \
  demo-api:1.0

sleep 2

echo "=== 8. Vérification Finale : Volume et Persistance (APRÈS recréation) ==="
echo "--- Volume demo_pgdata ---"
docker volume ls | grep demo_pgdata

echo "--- Produits en base (GET /products final) ---"
curl -s http://localhost:8080/products
echo ""

echo "=== 9. Nettoyage des conteneurs et du réseau (le volume est conservé) ==="
docker rm -f demo-api demo-db
docker network rm demo_net

# Pour supprimer le volume après vérification :
# docker volume rm demo_pgdata
```

---

## 2. Exécution du script et preuves de persistance

**Commande :**
```bash
$ bash volumes_ethan_bermond.sh
```

**Résultat de l'exécution :**
```text
=== 0. Nettoyage préventif ===
demo_net
=== 1. Build de l'image demo-api:1.0 ===
[+] Building 1.4s (11/11) FINISHED                                                                                                                             docker:desktop-linux
 => [internal] load build definition from Dockerfile                                                                                                                           0.0s
 => => transferring dockerfile: 397B                                                                                                                                           0.0s
 => [internal] load metadata for docker.io/library/node:22.11-alpine                                                                                                           1.0s
 => [auth] library/node:pull token for registry-1.docker.io                                                                                                                    0.0s
 => [internal] load .dockerignore                                                                                                                                              0.0s
 => => transferring context: 68B                                                                                                                                               0.0s
 => [1/5] FROM docker.io/library/node:22.11-alpine@sha256:b64ced2e7cd0a4816699fe308ce6e8a08ccba463c757c00c14cd372e3d2c763e                                                     0.0s
 => => resolve docker.io/library/node:22.11-alpine@sha256:b64ced2e7cd0a4816699fe308ce6e8a08ccba463c757c00c14cd372e3d2c763e                                                     0.0s
 => [internal] load build context                                                                                                                                              0.0s
 => => transferring context: 126B                                                                                                                                              0.0s
 => CACHED [2/5] WORKDIR /app                                                                                                                                                  0.0s
 => CACHED [3/5] COPY --chown=node:node package.json package-lock.json ./                                                                                                      0.0s
 => CACHED [4/5] RUN npm ci --omit=dev                                                                                                                                         0.0s
 => CACHED [5/5] COPY --chown=node:node server.js db.js ./                                                                                                                     0.0s
 => exporting to image                                                                                                                                                         0.1s
 => => exporting layers                                                                                                                                                        0.0s
 => => exporting manifest sha256:0211419825a5764248d6ad0ea92ad210feef3de6f63798cb1d4cab30ce5b2440                                                                              0.0s
 => => exporting config sha256:a702fd691fdeea08213e4e813748a326087c8e8c1598c630c6931afb0a477dc4                                                                                0.0s
 => => exporting attestation manifest sha256:fb5be5c20ffd5baddcdee77f9ed5f6dc2963ae2ce4f7a92bea9187c35bbed238                                                                  0.0s 
 => => exporting manifest list sha256:7a19acb0669241f421cf2d9d6e1a1d6334a7845ef0f4be974e22ddb57f1d628d                                                                         0.0s
 => => naming to docker.io/library/demo-api:1.0                                                                                                                                0.0s 
 => => unpacking to docker.io/library/demo-api:1.0                                                                                                                             0.0s 
                                                                                                                                                                                    
View build details: docker-desktop://dashboard/build/desktop-linux/desktop-linux/l8qw9j3ctytl76yujnhgxejs2
=== 2. Création du réseau et du volume nommé demo_pgdata ===
0f7f0a06ae3d7d61d1b46199a16f8f182bc4396b2722180f7c654b6d062228b6
demo_pgdata
=== 3. Lancement du conteneur demo-db (postgres:16-alpine) ===
5489a5e799bab8efd0f37e988255b3f2569b17f76e36171876798a8733694131
=== 4. Attente que la base de données soit prête ===
/var/run/postgresql:5432 - rejecting connections
En attente de PostgreSQL...
/var/run/postgresql:5432 - accepting connections
=== 5. Lancement de demo-api ===
9822c08c5254bf3a926a578947c4f7f0e6934752548714252231bec47d73a7d0
=== 6. Ajout du produit 'Casquette Démo' (POST /products) ===
{"id":37,"name":"Casquette D�mo","price_cents":1200,"created_at":"2026-10-24T16:37:58.389Z"}
--- Vérification AVANT suppression de demo-db (GET /products) ---
[{"id":37,"name":"Casquette D�mo","price_cents":1200,"created_at":"2026-10-24T16:37:58.389Z"},{"id":4,"name":"Casquette Démo","price_cents":1200,"created_at":"2026-10-24T16:29:05.232Z"},{"id":3,"name":"T-shirt conteneur","price_cents":1990,"created_at":"2026-10-24T16:29:01.927Z"},{"id":2,"name":"Mug Docker","price_cents":990,"created_at":"2026-10-24T16:29:01.927Z"},{"id":1,"name":"Sticker Demo","price_cents":150,"created_at":"2026-10-24T16:29:01.927Z"}]
=== 7. Suppression et recréation de demo-db avec le même volume ===
demo-db
29063bd562595a36d28f42142c579a1b055f847572e31b98ff8efafaefd9f61b
=== Attente du redémarrage de la base ===
/var/run/postgresql:5432 - accepting connections
=== Relance de demo-api ===
demo-api
8f15ddf4616dfd8434a560858d39cbd2f79ebda587b223664cf1d922310c9eb3
=== 8. Vérification Finale : Volume et Persistance (APRÈS recréation) ===
--- Volume demo_pgdata ---
local     demo_pgdata
--- Produits en base (GET /products final) ---
[{"id":37,"name":"Casquette D�mo","price_cents":1200,"created_at":"2026-10-24T16:37:58.389Z"},{"id":4,"name":"Casquette Démo","price_cents":1200,"created_at":"2026-10-24T16:29:05.232Z"},{"id":3,"name":"T-shirt conteneur","price_cents":1990,"created_at":"2026-10-24T16:29:01.927Z"},{"id":2,"name":"Mug Docker","price_cents":990,"created_at":"2026-10-24T16:29:01.927Z"},{"id":1,"name":"Sticker Demo","price_cents":150,"created_at":"2026-10-24T16:29:01.927Z"}]
=== 9. Nettoyage des conteneurs et du réseau (le volume est conservé) ===
demo-api
demo-db
demo_net
```
---
## Liens

- Repo GitHub : https://github.com/ynov-x-anthony/BERMOND_Ethan_demo-api
