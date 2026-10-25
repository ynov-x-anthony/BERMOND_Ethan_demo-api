# Projet demo-api — Stack Docker Compose (Étape 4)

Déploiement complet de la stack `demo-api` (API Node.js, PostgreSQL 16 et Adminer) orchestrée avec Docker Compose, incluant l'isolation réseau, la persistance des données, les healthchecks et la gestion des mots de passe via Docker Secrets.

## Prérequis

- **Docker** et **Docker Compose** (inclus dans Docker Desktop)
- **Git**

## Installation et démarrage

1. **Cloner le dépôt et configurer les variables d'environnement :**
   ```bash
   cp .env.example .env
   ```

2. **Créer le fichier secret contenant le mot de passe de la base de données :**
   ```bash
   echo -n "demo" > db_password.txt
   ```

3. **Lancer la stack en arrière-plan (avec build de l'API) :**
   ```bash
   docker compose up -d --build
   ```

## URLs des services

- **API (`demo-api`)** : http://localhost:8080 (Routes : `/`, `/health`, `/products`)
- **Adminer (Interface BDD)** : http://localhost:8081
    - *Système* : PostgreSQL
    - *Serveur* : `db`
    - *Utilisateur* : `demo` / *Mot de passe* : `demo` / *Base* : `demo`

## Repartir de zéro (Reset complet)

Pour arrêter les conteneurs, supprimer les réseaux **et** supprimer le volume de données `pgdata` :

```bash
docker compose down -v
```

---

## Preuves de fonctionnement et Tests

### 1. État des conteneurs (`docker compose ps` avec `db` healthy)

**Commande :**
```bash
$ docker compose ps
```
**Résultat :**
```text
NAME                 IMAGE                COMMAND                  SERVICE   CREATED          STATUS                    PORTS
demo-api-adminer-1   adminer:4            "entrypoint.sh php -…"   adminer   30 seconds ago   Up 29 seconds             0.0.0.0:8081->8080/tcp
demo-api-api-1       demo-api-api         "docker-entrypoint.s…"   api       30 seconds ago   Up 24 seconds (healthy)   0.0.0.0:8080->3000/tcp
demo-api-db-1        postgres:16-alpine   "docker-entrypoint.s…"   db        30 seconds ago   Up 29 seconds (healthy)   5432/tcp
```

### 2. Test de l'API et persistance du produit « Gourde »

**Récupération initiale (`GET /products`) :**
```bash
$ curl -s http://localhost:8080/products
[{"id":1,"name":"Sticker Demo","price_cents":150},{"id":2,"name":"Mug Docker","price_cents":990},{"id":3,"name":"T-shirt conteneur","price_cents":1990}]
```

**Ajout du produit « Gourde » (`POST /products`) :**
```bash
$ curl -s -X POST -H 'content-type: application/json' -d '{"name":"Gourde","price_cents":900}' http://localhost:8080/products
{"id":4,"name":"Gourde","price_cents":900}
```

**Vérification de la persistance après `docker compose down` puis `docker compose up -d` :**
```bash
$ docker compose down
$docker compose up -d$ curl -s http://localhost:8080/products
[{"id":1,"name":"Sticker Demo","price_cents":150},{"id":2,"name":"Mug Docker","price_cents":990},{"id":3,"name":"T-shirt conteneur","price_cents":1990},{"id":4,"name":"Gourde","price_cents":900}]
```

## Liens

- Repo GitHub : https://github.com/ynov-x-anthony/BERMOND_Ethan_demo-api