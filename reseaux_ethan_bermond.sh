#!/usr/bin/env bash
set -e

# Empêche Git Bash sur Windows de convertir les chemins Linux en chemins Windows
export MSYS_NO_PATHCONV=1

echo "=== 0. Nettoyage préventif ==="
docker rm -f demo-api demo-db 2>/dev/null || true
docker network rm demo_front demo_back 2>/dev/null || true

echo "=== 1. Build de l'image demo-api:1.0 ==="
docker build -t demo-api:1.0 ./api

echo "=== 2. Création des réseaux personnalisés demo_front et demo_back ==="
docker network create demo_front
docker network create demo_back

echo "=== 3. Lancement de demo-db (connecté uniquement à demo_back, sans -p) ==="
docker run -d --name demo-db \
  --network demo_back \
  -v "$(pwd)/db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro" \
  -e POSTGRES_USER=demo \
  -e POSTGRES_PASSWORD=demo \
  -e POSTGRES_DB=demo \
  postgres:16-alpine

echo "=== Attente que PostgreSQL soit prêt ==="
until docker exec demo-db pg_isready -U demo -d demo; do
  echo "En attente de PostgreSQL..."
  sleep 1
done

echo "=== 4. Lancement de demo-api (connecté à demo_front ET demo_back, publié sur 8080) ==="
docker run -d --name demo-api \
  --network demo_front \
  -p 8080:3000 \
  -e PGHOST=demo-db \
  demo-api:1.0

# Connexion de demo-api au second réseau (demo_back)
docker network connect demo_back demo-api

sleep 2

echo ""
echo "=== 5. Vérifications et preuves d'isolation réseau ==="

echo "--- 1. Résolution DNS de demo-db depuis demo-api (OK attendu) ---"
docker exec demo-api getent hosts demo-db

echo "--- 2. Tentative de connexion à demo-db depuis un conteneur tiers sur demo_front (Échec attendu) ---"
docker run --rm --network demo_front alpine nc -zv demo-db 5432 2>&1 || echo "-> Échec attendu : demo-db est bien isolé de demo_front"

echo "--- 3. Adresses IPv4 de demo-db ---"
docker inspect -f '{{range $net, $conf := .NetworkSettings.Networks}}{{$net}}: {{.IPAMConfig}} {{.IPAddress}}{{"\n"}}{{end}}' demo-db

echo "--- 3bis. Adresses IPv4 de demo-api ---"
docker inspect -f '{{range $net, $conf := .NetworkSettings.Networks}}{{$net}}: {{.IPAMConfig}} {{.IPAddress}}{{"\n"}}{{end}}' demo-api

echo "--- 4. Résultat de curl localhost:8080/products ---"
curl -s http://localhost:8080/products
echo ""

echo ""
echo "=== 6. Nettoyage final ==="
docker rm -f demo-api demo-db
docker network rm demo_front demo_back