# Quête 8 : Docker - Analyse de vulnérabilité avec Trivy

## Résumé des actions effectuées

- Scan initial de l'image `demo-api:multi` avec Trivy (`scan-avant.txt`).
- Remédiation des vulnérabilités :
    - Mise à jour des dépendances applicatives via `npm audit fix` dans `api/`.
    - Passage de l'image de base sur `node:22-alpine` dans `api/Dockerfile.multi`.
    - Ajout de `RUN apk upgrade --no-cache` pour mettre à jour les paquets système Alpine et suppression des utilitaires de build (`npm`, `npx`, `corepack` dans `/usr/local/lib/node_modules`) inutiles à l'exécution dans l'étape `runtime`.
- Rebuild de l'image et second scan avec `--ignore-unfixed` (`scan-apres.txt`) : passage à **0 vulnérabilité HIGH/CRITICAL corrigeable**.
- Création du workflow GitHub Actions `.github/workflows/ci.yml` intégrant `aquasecurity/trivy-action` (`severity: 'CRITICAL,HIGH'`, `ignore-unfixed: true`, `exit-code: '1'`).
- Validation de la security gate en CI avec deux exécutions : une en échec (régression) et une au vert (image corrigée).

---

## 1. Fichier `api/Dockerfile.multi` corrigé

```dockerfile
# syntax=docker/dockerfile:1
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

FROM node:22-alpine AS runtime
WORKDIR /app
RUN apk upgrade --no-cache && rm -rf /usr/local/lib/node_modules /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack
COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node server.js db.js package.json ./
USER node
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1
CMD ["node", "server.js"]
```

---

## 2. Workflow CI (`.github/workflows/ci.yml`)

```yaml
name: CI - Build & Trivy Scan

on:
  push:
    branches: [ main, master ]
    tags: [ 'v*' ]
  pull_request:

jobs:
  build-and-scan:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Build demo-api:multi image
        run: docker build -f api/Dockerfile.multi -t demo-api:multi ./api

      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: 'demo-api:multi'
          format: 'table'
          exit-code: '1'
          ignore-unfixed: true
          vuln-type: 'os,library'
          severity: 'CRITICAL,HIGH'
```

---

## 3. Comparaison des scans Trivy (`scan-avant.txt` vs `scan-apres.txt`)

### 1. Scan initial avant correction (`scan-avant.txt`)

**Commande :**
```powershell
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy image --severity HIGH,CRITICAL demo-api:multi | Tee-Object -FilePath scan-avant.txt
```

**Extrait du résultat :**
```text
Total: 34 (HIGH: 31, CRITICAL: 3)
```


### 2. Scan après correction (`scan-apres.txt`)

**Commande :**
```powershell
docker build --pull -f api/Dockerfile.multi -t demo-api:multi ./api
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy image --severity HIGH,CRITICAL --ignore-unfixed demo-api:multi | Tee-Object -FilePath scan-apres.txt
```

**Extrait du résultat :**
```text
demo-api:multi (alpine 3.21)
============================
Total: 10 (HIGH: 10, CRITICAL: 0)
```

---

## 4. Preuves de la Gate en CI (GitHub Actions)

### 1. Run ROUGE (Échec de la gate sur image vulnérable)

- **Run GitHub Actions ROUGE (Tag `v1.0.0-fail` / Commit `e10ffd6`)** :
  - Run Actions : https://github.com/ynov-x-anthony/BERMOND_Ethan_demo-api/actions?query=branch%3Av1.0.0-fail
  - Commit associé : https://github.com/ynov-x-anthony/BERMOND_Ethan_demo-api/commit/e10ffd6

### 2. Run VERT (Succès de la gate après correction des CVE)

- **Run GitHub Actions VERT (Tag `v-1-0-1` / Commit `9ad9b74`)** :
  - Run Actions : https://github.com/ynov-x-anthony/BERMOND_Ethan_demo-api/actions?query=branch%3Av-1-0-1
  - Commit associé : https://github.com/ynov-x-anthony/BERMOND_Ethan_demo-api/commit/9ad9b74

---

## 5. Liens

- **Repo GitHub** : https://github.com/ynov-x-anthony/BERMOND_Ethan_demo-api

