# Quête 2 : Dockerfile de demo-api

## Résumé des actions effectuées

- Écriture de `api/Dockerfile` : base épinglée `node:22-alpine`, dépendances installées dans une couche séparée (`COPY package.json package-lock.json` puis `RUN npm ci --omit=dev`), puis copie du code (`server.js`, `db.js`), `EXPOSE 3000`, `CMD ["node", "server.js"]` en exec form.
- Ajout de `api/.dockerignore` (`node_modules`, `.git`, `*.md`, `.env*`).
- Build : `docker build -t demo-api:1.0 ./api`
- Test :

```bash
$ docker run -d --name api -p 8080:3000 demo-api:1.0
$ curl.exe -s http://localhost:8080/health
{"status":"UP"}
$ curl.exe -s http://localhost:8080/
{"ok":true,"app":"demo-api","version":"dev"}
$ docker rm -f api
```

## Preuve du cache

Après modification d'un fichier source, exécution de `docker build -t demo-api:1.0 --progress=plain ./api` :

```text
#6 [1/5] FROM docker.io/library/node:22-alpine@sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402
#6 resolve docker.io/library/node:22-alpine@sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402 0.0s done
#6 DONE 0.0s

#7 [3/5] COPY package.json package-lock.json ./
#7 CACHED

#8 [4/5] RUN npm ci --omit=dev
#8 CACHED

#9 [2/5] WORKDIR /app
#9 CACHED

#10 [5/5] COPY server.js db.js ./
#10 CACHED
```

L'installation des dépendances (`RUN npm ci`) est bien récupérée depuis le cache.

## docker image ls demo-api

```text
IMAGE          ID             DISK USAGE   CONTENT SIZE   EXTRA
demo-api:1.0   d41f68a7df6f        252MB         63.2MB        
```

## Liens

- Repo GitHub : https://github.com/ynov-x-anthony/BERMOND_Ethan_demo-api
- Image publiée : _à compléter après le push_