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