# Quête 3 : Dockerfile et sécurité

## Résumé des actions effectuées

- Modification de `api/Dockerfile` :
    - Base épinglée sur `node:22.11-alpine`.
    - Copie des fichiers avec attribution des droits à l'utilisateur non-root (`COPY --chown=node:node ...`).
    - Ajout d'un `HEALTHCHECK` sur la route `/health`.
    - Passage sur l'utilisateur non-privilégié `USER node` avant le `CMD`.
- Vérification de `api/.dockerignore` (`node_modules`, `.git`, `*.md`, `.env*`).
- Build de l'image durcie : `docker build -t demo-api:hardened ./api`

## Dockerfile durci (`api/Dockerfile`)

```dockerfile
FROM node:22.11-alpine
WORKDIR /app
COPY --chown=node:node package.json package-lock.json ./
RUN npm ci --omit=dev
COPY --chown=node:node server.js db.js ./
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1
USER node
CMD ["node", "server.js"]
```

## Preuve de l'utilisateur non-root (`id`)

```text
$ docker run --rm demo-api:hardened id
uid=1000(node) gid=1000(node) groups=1000(node),1000(node)
```

## Commande `docker run` durcie utilisée


```powershell
docker run -d --name api -p 8080:3000 --read-only --tmpfs /tmp:size=16m --cap-drop ALL --security-opt no-new-privileges --pids-limit 200 --memory 256m --cpus 1 --network demo_net -e PGHOST=demo-db demo-api:hardened
```

## Preuves du durcissement

### 1. Test de santé de l'API (`/health`)
**Commande :**
```text
$ curl.exe -s http://localhost:8080/health
```
**Résultat :**
```text
{"status":"UP"}
```
### 2. Test d'écriture refusée sur le système de fichiers (`/app` en lecture seule)
**Commande :**
```text
$ docker exec api sh -c "touch /app/x 2>&1 || echo 'rootfs read-only OK'"
```
**Résultat :**
```text
touch: /app/x: Read-only file system
rootfs read-only OK
```
### 3. Inspection de la sécurité du conteneur (`docker inspect`)
**Commande :**
```text
$ docker inspect -f "readonly={{.HostConfig.ReadonlyRootfs}} capdrop={{.HostConfig.CapDrop}}" api
```
**Résultat :**
```text
readonly=true capdrop=[ALL]
```
## Liens

- Repo GitHub : https://github.com/ynov-x-anthony/BERMOND_Ethan_demo-api