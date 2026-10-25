#Quête 6 : Docker - Les réseaux

## Résumé des actions effectuées

- Création du script `reseaux_ethan_bermond.sh` mettant en place une architecture réseau cloisonnée :
    - Création de deux réseaux bridge personnalisés : `demo_front` et `demo_back`.
    - Lancement de `demo-db` (`postgres:16-alpine` avec `db/init.sql`) attaché **uniquement** au réseau `demo_back` et sans aucun port exposé sur l'hôte (pas de `-p`).
    - Lancement de `demo-api` exposé sur le port `8080:3000`, connecté à la fois à `demo_front` et à `demo_back` (`docker network connect`).
    - Vérification de la résolution DNS interne (`getent hosts`), de l'impossibilité pour un conteneur tiers situé sur `demo_front` de joindre `demo-db`, inspection des adresses IPv4 attribuées et test de la route `/products`.

---

## 1. Script `reseaux_ethan_bermond.sh`

```bash
#!/usr/bin/env bash
set -e

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

docker network connect demo_back demo-api

sleep 2

echo ""
echo "=== 5. Vérifications et preuves d'isolation réseau ==="

echo "--- 1. Résolution DNS de demo-db depuis demo-api (OK attendu) ---"
docker exec demo-api getent hosts demo-db

echo "--- 2. Tentative de connexion à demo-db depuis un conteneur tiers sur demo_front (Échec attendu) ---"
docker run --rm --network demo_front alpine nc -zv demo-db 5432 2>&1 || echo "-> Échec attendu : demo-db est bien isolé de demo_front"

echo "--- 3. Adresses IPv4 de demo-db ---"
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAMConfig}} {{.IPAddress}}{{"\n"}}{{end}}' demo-db

echo "--- 3bis. Adresses IPv4 de demo-api ---"
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAMConfig}} {{.IPAddress}}{{"\n"}}{{end}}' demo-api

echo "--- 4. Résultat de curl localhost:8080/products ---"
curl -s http://localhost:8080/products
echo ""

echo ""
echo "=== 6. Nettoyage final ==="
docker rm -f demo-api demo-db
docker network rm demo_front demo_back
```

---

## 2. Exécution du script et preuves

**Commande :**
```bash
$ bash reseaux_ethan_bermond.sh
```

**Résultat de l'exécution :**

### 1. Résolution de `demo-db` depuis `demo-api` (OK)
```text
--- 1. Résolution DNS de demo-db depuis demo-api (OK attendu) ---
172.19.0.2      demo-db  demo-db
```

### 2. Échec de connexion depuis le conteneur tiers sur `demo_front`
```text
--- 2. Tentative de connexion à demo-db depuis un conteneur tiers sur demo_front (Échec attendu) ---
nc: bad address 'demo-db'
-> Échec attendu : demo-db est bien isolé de demo_front
```

### 3. Adresses IPv4 de `demo-db` et `demo-api` sur chaque réseau
```text
--- 3. Adresses IPv4 de demo-db ---
<nil> 172.19.0.2

--- 3bis. Adresses IPv4 de demo-api ---
<nil> 172.19.0.3
<nil> 172.18.0.2
```
*(On voit bien que `demo-db` ne possède qu'une seule IP sur `demo_back`, tandis que `demo-api` possède deux interfaces IP : une sur `demo_front` et une sur `demo_back`).*

### 4. Test de l'API (`GET /products`)
```text
--- 4. Résultat de curl localhost:8080/products ---
[{"id":1,"name":"Sticker Demo","price_cents":150},{"id":2,"name":"Mug Docker","price_cents":990},{"id":3,"name":"T-shirt conteneur","price_cents":1990}]
```

---

## Liens

- Repo GitHub : https://github.com/ynov-x-anthony/BERMOND_Ethan_demo-api
