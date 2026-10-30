# Quête 9 : Docker - Microservices et déploiement continu

## Résumé des actions effectuées

- **Création du microservice `notifier/`** :
    - Serveur Express minimal (`notifier/server.js`) exposant `GET /health` et `POST /notify` (journalise le corps JSON reçu sur `stdout`).
    - `notifier/Dockerfile` multi-étapes durci : image de base épinglée (`node:22.14-alpine3.21`), mise à jour de sécurité (`apk upgrade --no-cache` et suppression de `npm`/`corepack` au runtime), utilisateur non-root (`USER node`) et `HEALTHCHECK`.
- **Intégration dans `compose.yml` et appel Best-Effort dans `api`** :
    - Ajout du service `notifier` connecté **uniquement** au réseau interne `demo_back`, sans exposition de port sur l'hôte (`ports:` absent), configuré via la variable `PORT=3001`.
    - Mise à jour de `POST /products` dans `api/server.js` pour envoyer un événement `product_created` à `http://notifier:3001/notify` en *best-effort* (ne bloque jamais la réponse `201 Created` si `notifier` est injoignable).
- **Pipeline CI/CD en Matrix (`api`, `notifier`), publication GHCR et Job `deploy`** :
    - Évolution de `.github/workflows/ci.yml` avec `strategy.matrix.service: [api, notifier]` : chaque service est buildé, scanné par Trivy (`exit-code: '1'`, `ignore-unfixed: true`, `severity: 'CRITICAL,HIGH'`) et publié séparément sur `ghcr.io/ynov-x-anthony/bermond_ethan_demo-api/<service>`.
    - Ajout du job `deploy` (`needs: image`, déclenché uniquement sur les tags `v*`) qui simule le déploiement cible sur le runner GitHub via `docker compose pull && docker compose up -d` et vérifie la réception d'une notification après un `POST /products`.

---

## 1. Code et configuration ajoutés

### A. `notifier/server.js`

```javascript
const express = require('express');
const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3001;

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', service: 'notifier' });
});

app.post('/notify', (req, res) => {
  console.log('[NOTIFIER] Notification reçue :', JSON.stringify(req.body));
  res.status(200).json({ received: true });
});

app.listen(PORT, () => {
  console.log(`[NOTIFIER] Écoute sur le port ${PORT}`);
});
```

### B. `notifier/Dockerfile`

```dockerfile
# syntax=docker/dockerfile:1
FROM node:22.14-alpine3.21 AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev

FROM node:22.14-alpine3.21 AS runtime
WORKDIR /app
RUN apk upgrade --no-cache && \
    rm -rf /usr/local/lib/node_modules /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack
COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node server.js package.json ./
USER node
EXPOSE 3001
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3001/health || exit 1
CMD ["node", "server.js"]
```

### C. Extrait de `api/server.js` (Appel Best-Effort dans `POST /products`)

```javascript
app.post('/products', async (req, res) => {
  const name = (req.body && req.body.name || '').trim();
  const priceCents = Number(req.body && req.body.price_cents);
  if (!name || !Number.isInteger(priceCents) || priceCents < 0) {
    return res.status(400).json({ error: 'name (string) et price_cents (entier >= 0) requis' });
  }
  try {
    const product = await db.addProduct(name, priceCents);

    // Appel best-effort vers notifier : ne bloque pas la reponse 201 si notifier est absent/down
    fetch(NOTIFIER_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ event: 'product_created', product }),
    }).catch((err) => {
      console.warn(JSON.stringify({
        level: 'warn', msg: 'notifier unreachable (best-effort)', err: err.message,
      }));
    });

    res.status(201).json(product);
  } catch (err) {
    res.status(503).json({ error: 'db_unavailable', detail: err.message });
  }
});
```

### D. Fichier `compose.yml` mis à jour

```yaml
services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-demo}
      POSTGRES_DB: ${POSTGRES_DB:-demo}
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_password
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-demo} -d ${POSTGRES_DB:-demo}"]
      interval: 5s
      timeout: 3s
      retries: 5
    networks:
      - demo_back

  notifier:
    image: ${NOTIFIER_IMAGE:-demo-notifier:local}
    build: ./notifier
    environment:
      PORT: 3001
    restart: unless-stopped
    networks:
      - demo_back

  api:
    image: ${API_IMAGE:-demo-api:local}
    build: ./api
    ports:
      - "${API_PORT:-8080}:3000"
    environment:
      PGHOST: db
      PGUSER: ${POSTGRES_USER:-demo}
      PGDATABASE: ${POSTGRES_DB:-demo}
      PGPASSWORD: ${PGPASSWORD:-demo}
      NOTIFIER_URL: http://notifier:3001/notify
    secrets:
      - db_password
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - demo_front
      - demo_back

  adminer:
    image: adminer:4
    ports:
      - "${ADMINER_PORT:-8081}:8080"
    depends_on:
      - db
    networks:
      - demo_back

volumes:
  pgdata:

networks:
  demo_front:
  demo_back:

secrets:
  db_password:
    file: ./db_password.txt
```

### E. Workflow `.github/workflows/ci.yml` (Matrix + GHCR + Deploy)

```yaml
name: CI/CD - Matrix Build, Trivy, GHCR & Deploy

on:
  push:
    branches: [ main, master ]
    tags: [ 'v*' ]
  pull_request:

env:
  REGISTRY: ghcr.io

jobs:
  image:
    name: Build, Scan & Push (${{ matrix.service }})
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    strategy:
      matrix:
        service: [api, notifier]
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set lower case repository name
        run: echo "REPO_LOWER=$(echo '${{ github.repository }}' | tr '[:upper:]' '[:lower:]')" >> $GITHUB_ENV

      - name: Build ${{ matrix.service }} image
        run: |
          docker build -t ${{ env.REGISTRY }}/${{ env.REPO_LOWER }}/${{ matrix.service }}:${{ github.ref_name }} ./${{ matrix.service }}
          docker tag ${{ env.REGISTRY }}/${{ env.REPO_LOWER }}/${{ matrix.service }}:${{ github.ref_name }} ${{ env.REGISTRY }}/${{ env.REPO_LOWER }}/${{ matrix.service }}:latest

      - name: Run Trivy vulnerability scanner (${{ matrix.service }})
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: '${{ env.REGISTRY }}/${{ env.REPO_LOWER }}/${{ matrix.service }}:${{ github.ref_name }}'
          format: 'table'
          exit-code: '1'
          ignore-unfixed: true
          vuln-type: 'os,library'
          severity: 'CRITICAL,HIGH'

      - name: Log in to GitHub Container Registry (GHCR)
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Push ${{ matrix.service }} to GHCR
        if: github.event_name != 'pull_request'
        run: |
          docker push ${{ env.REGISTRY }}/${{ env.REPO_LOWER }}/${{ matrix.service }}:${{ github.ref_name }}
          docker push ${{ env.REGISTRY }}/${{ env.REPO_LOWER }}/${{ matrix.service }}:latest

  deploy:
    name: Deploy Stack from GHCR
    needs: image
    if: startsWith(github.ref, 'refs/tags/v')
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: read
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set lower case repository name
        run: echo "REPO_LOWER=$(echo '${{ github.repository }}' | tr '[:upper:]' '[:lower:]')" >> $GITHUB_ENV

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Prepare environment & secrets on target
        run: |
          cp .env.example .env
          echo -n "demo" > db_password.txt
          echo "API_IMAGE=${{ env.REGISTRY }}/${{ env.REPO_LOWER }}/api:${{ github.ref_name }}" >> .env
          echo "NOTIFIER_IMAGE=${{ env.REGISTRY }}/${{ env.REPO_LOWER }}/notifier:${{ github.ref_name }}" >> .env

      - name: Deploy with Docker Compose (pull & up -d)
        run: |
          docker compose pull
          docker compose up -d
          sleep 8
          docker compose ps

      - name: Verify deployed stack & Notifier logs
        run: |
          curl -f -s -X POST http://localhost:8080/products \
            -H "Content-Type: application/json" \
            -d '{"name":"Clavier meca","price_cents":5900}'
          sleep 2
          docker compose logs notifier | tail -5
          docker compose down -v
```

---

## 2. Preuves d'exécution et Logs de `notifier`

### 1. Création d'un produit et réception dans les logs de `notifier`

**Commandes :**
```powershell
docker compose up -d --build
curl.exe -s -X POST http://localhost:8080/products -H "Content-Type: application/json" -d '{\"name\":\"Clavier meca\",\"price_cents\":5900}'
docker compose logs notifier | Select-Object -Last 5
```

**Résultat (`POST /products`) :**
```json
{"id":5,"name":"Clavier meca","price_cents":5900,"created_at":"2026-10-30T15:10:12.410Z"}
```

**Extrait des logs (`docker compose logs notifier`) :**
```text
bermond_ethan_demo-api-notifier-1  | [NOTIFIER] Écoute sur le port 3001
bermond_ethan_demo-api-notifier-1  | [NOTIFIER] Notification reçue : {"event":"product_created","product":{"id":5,"name":"Clavier meca","price_cents":5900,"created_at":"2026-10-30T15:10:12.410Z"}}
```

[![Logs du service notifier](./image_preuves/preuve_notifier_logs.png)](./image_preuves/preuve_notifier_logs.png)

### 2. Test de résilience (Best-Effort) avec `notifier` arrêté

**Commandes :**
```powershell
docker compose stop notifier
curl.exe -i -s -X POST http://localhost:8080/products -H "Content-Type: application/json" -d '{\"name\":\"Souris sans fil\",\"price_cents\":2900}'
docker compose start notifier
```

**Résultat (L'API répond bien `201 Created` malgré l'arrêt de `notifier`) :**
```text
HTTP/1.1 201 Created
Content-Type: application/json; charset=utf-8

{"id":6,"name":"Souris sans fil","price_cents":2900,"created_at":"2026-10-30T15:12:04.118Z"}
```

---

## 3. Preuve du Pipeline CI/CD (Matrix `image` x2 + `deploy` sur Tag `v1.5.2`)

> **Note sur la cible de déploiement :** Comme proposé dans les conseils de l'étape, le déploiement est simulé directement sur le runner GitHub Actions qui authentifie la session sur `ghcr.io`, exécute `docker compose pull && docker compose up -d` à partir des deux images fraîchement publiées sur GHCR, puis vérifie qu'un `POST /products` déclenche bien la trace dans `docker compose logs notifier`.

[![Run GitHub Actions Matrix + Deploy](./image_preuves/preuve_ci_matrix_deploy.png)](./image_preuves/preuve_ci_matrix_deploy.png)

---

## 4. Liens

- **Repo GitHub** : https://github.com/ynov-x-anthony/BERMOND_Ethan_demo-api
- **Run GitHub Actions vert (Matrix `api` + `notifier` + job `deploy` sur tag `v1.5.2`)** : https://github.com/ynov-x-anthony/BERMOND_Ethan_demo-api/actions?query=branch%3Av1.1.0
- **Packages GHCR (`api` & `notifier`)** : https://github.com/orgs/ynov-x-anthony/packages?repo_name=BERMOND_Ethan_demo-api