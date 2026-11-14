# Pipeline CI/CD DevSecOps sur AWS (version AWS Academy Learner Lab)

API Flask conteneurisée, contrôles de sécurité automatisés (Gitleaks, Semgrep, Trivy, Checkov)
et déploiement sur AWS ECS/Fargate depuis GitHub Actions.

## Spécificités du Learner Lab (à expliquer à l'oral)

| Contrainte du lab | Choix dans le projet |
|---|---|
| Régions limitées (us-east-1, us-west-2) | Région `us-east-1` |
| Impossible de créer des rôles IAM | Utilisation du rôle existant `LabRole` (`data "aws_iam_role"`) |
| OIDC GitHub -> AWS impossible (création de fournisseur et de rôle) | Identifiants **temporaires** du lab dans des secrets GitHub, à renouveler à chaque session |
| Session limitée (~4 h) | Les secrets GitHub doivent être remis à jour à chaque démarrage du lab |

L'architecture cible de production (OIDC, rôle au moindre privilège, aucune clé stockée) est conservée
dans `production/oidc.tf.example`. Elle n'est pas appliquée dans le lab.

## Structure du projet

```
.github/workflows/devsecops.yml   Pipeline GitHub Actions          -> étapes 5 et 6
.semgrep/rules.yml                Règle SAST Semgrep               -> étape 3
.checkov.yaml                     Exceptions Checkov documentées   -> étapes 3 et 4
app/__init__.py, app/app.py       API Flask (/ et /health)         -> étape 1
tests/test_app.py, pytest.ini     Tests unitaires                  -> étape 1
requirements.txt                  Dépendances Python               -> étapes 1 et 2
Dockerfile, .dockerignore         Image Docker                     -> étape 2
Makefile                          Raccourcis (tests, scans)        -> étape 3
terraform/                        Infrastructure AWS               -> étape 4
  main.tf                         ECR, ECS/Fargate, réseau, logs, LabRole
  kms.tf                          Clés KMS (ECR et logs)
  variables.tf, outputs.tf        Variables et sorties
  terraform.tfvars.example        Modèle de configuration
production/oidc.tf.example        OIDC GitHub -> AWS (cible prod)  -> à présenter, pas appliqué
scenarios/demo_s3_public.tf.txt   Scénario de démo Checkov         -> étape 7
presentation/soutenance.pptx      Présentation orale               -> étape 8
```

---

## Étapes 0 à 3 (déjà faites)

Tests locaux, image Docker, Semgrep et Checkov via Docker (voir tes captures 01 à 05).
Sous Windows, Checkov et Semgrep se lancent par Docker :

```
docker run --rm -v "%cd%:/tf" -w /tf bridgecrew/checkov -d terraform --framework terraform --config-file .checkov.yaml
docker run --rm -v "%cd%:/src" -w /src semgrep/semgrep semgrep --config .semgrep/rules.yml --error --metrics=off app tests
```

## Étape 4 : Créer l'infrastructure dans le Learner Lab

Fichiers : tout le dossier `terraform/`, `.checkov.yaml`

1. Démarre le lab (point vert) et copie les identifiants depuis **AWS Details > AWS CLI > Show**
   dans `%USERPROFILE%\.aws\credentials` (fichier sans extension `.txt`), région `us-east-1` dans `config`.
2. Vérifie : `aws sts get-caller-identity`.
3. Installe Terraform si besoin : `winget install Hashicorp.Terraform` (puis rouvrir le terminal).

```
cd terraform
copy terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt
terraform validate
terraform plan -out plan.tfplan
terraform apply plan.tfplan
terraform output
```

Remarques :
- Juste après `apply`, le service ECS essaie de démarrer l'image `:bootstrap` qui n'existe pas encore :
  c'est normal. Le premier pipeline (étape 6) déploie la vraie image.
- Si `apply` échoue sur une ressource (par exemple KMS) avec `AccessDenied`, envoie le message exact :
  le lab bloque certaines actions et on adaptera ce point.

## Étape 5 : Dépôt GitHub et secrets

1. Crée un dépôt GitHub, puis Settings > Secrets and variables > Actions > **New repository secret**.
2. Crée 3 secrets avec les valeurs de **AWS Details** :
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_SESSION_TOKEN`
3. **À chaque nouvelle session du lab**, ces 3 valeurs changent : mets-les à jour, sinon le job de
   déploiement échoue avec `ExpiredToken`. Les contrôles de sécurité, eux, n'ont pas besoin d'AWS.
4. Ne commite jamais ces valeurs dans le code (Gitleaks les détecterait).

## Étape 6 : Premier déploiement par le pipeline

```
git init -b main
git add .
git commit -m "Projet DevSecOps initial"
git remote add origin https://github.com/TON_USER/TON_REPO.git
git push -u origin main
```

Onglet Actions : le job « Contrôles de sécurité » puis « Build et déploiement AWS » doivent passer au vert.
Pour l'IP publique de l'API (région us-east-1) :

```
set R=us-east-1
aws ecs list-tasks --cluster devsecops-demo --region %R%
aws ecs describe-tasks --cluster devsecops-demo --tasks ARN_DE_LA_TACHE --region %R% --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" --output text
aws ec2 describe-network-interfaces --network-interface-ids ENI_ID --region %R% --query "NetworkInterfaces[0].Association.PublicIp" --output text
curl.exe http://IP_PUBLIQUE:8080/health
```

Les logs de l'API sont dans CloudWatch, groupe `/ecs/devsecops-demo`.

## Étape 7 : Démonstration des 3 scénarios

Sur une branche de test avec une Pull Request (le job de sécurité tourne sur les PR, le déploiement
seulement sur `main`). Prends une capture de chaque échec.

**Scénario 1 : secret commité (Semgrep / Gitleaks)**
```
git checkout -b demo-secret
echo db_password = "SuperSecret123" > app\demo_secret.py
git add . && git commit -m "demo secret" && git push -u origin demo-secret
```
Semgrep (règle `no-hardcoded-passwords`) bloque la ligne. Gitleaks fait échouer le pipeline (il ne
« rejette » pas le push) : vérifie les logs de son étape.

**Scénario 2 : dépendance vulnérable (Trivy)**
```
git checkout main && git checkout -b demo-cve
echo requests==2.19.1 >> requirements.txt
git add . && git commit -m "demo cve" && git push -u origin demo-cve
```
Trivy doit échouer (CVE HIGH/CRITICAL avec correctif disponible).

**Scénario 3 : ressource Terraform publique (Checkov)**
```
git checkout main && git checkout -b demo-s3
copy scenarios\demo_s3_public.tf.txt terraform\demo_s3_public.tf
git add . && git commit -m "demo s3 public" && git push -u origin demo-s3
```
Testé en local : Checkov signale `CKV_AWS_53`, `54`, `55` et `56`. Ne fusionne jamais ces branches dans `main`.

## Étape 8 : Présentation

Fichier : `presentation/soutenance.pptx`. À corriger avant de présenter :
- Slide 1 : nom, enseignant, établissement, année (placeholders).
- Slide 6 : ajouter la limite du Learner Lab (OIDC non applicable, `LabRole`, identifiants temporaires).
- Slide 7 : vraies captures, et « Pipeline échoué » au lieu de « Push rejeté » pour Gitleaks.
- Slide 8 : remplacer les chiffres par tes mesures réelles (durée du workflow, résultats des 3 scénarios).

## Étape 9 : Nettoyage (important pour le crédit du lab)

```
cd terraform
terraform destroy
```

---

## Ce qui a été vérifié, et ce qui ne l'a pas été

Vérifié : `pytest` (2 tests), Semgrep, Checkov (29 contrôles OK, 0 échec sur le Terraform du lab).
Vérifié dans ton lab : `LabRole` existe, les commandes KMS, ECR et ECS répondent.
Non vérifié : `terraform plan/apply`, le workflow GitHub Actions, Gitleaks et Trivy.
