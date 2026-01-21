# Réaliser un traitement dans un environnement Big Data sur le Cloud avec Spark

## Introduction
Ce projet est basé sur le dataset [Fruits-360](https://www.kaggle.com/datasets/moltean/fruits), qui contient ~90k photos détourées de fruits et légumes. L’objectif est de mettre en place un pipeline **scalable** capable de fonctionner en local puis sur **AWS EMR** avec **Spark**.

Nous réalisons deux traitements principaux :
- **Extraction de features d’images** via un modèle pré‑entraîné (transfer learning avec **MobileNetV2**).
- **Réduction de dimension** des features par **PCA (MLlib)** et export des résultats (CSV/Parquet).

## Contenu du repository
- `notebook/P8_Notebook_Linux_PySpark_Local_V1.0.ipynb` : tests **en local** pour valider le script et le pipeline.
- `notebook/P8_Notebook_Linux_EMR_PySpark_V1.0.ipynb` : notebook **à exécuter sur AWS EMR** (volume d’images plus important).
- `bootstrap.sh` : script de **bootstrap EMR** (dépendances Python et versions pin‑nées).

## Article associé
Retrouvez l’article de présentation du projet : https://bigheadmax.github.io/07-traitement-aws-spark.html

---

# Mise en place de l’environnement Big Data

## 1) Installation de Spark en local (tests)
Sous Windows, passez par **WSL** (Ubuntu recommandé). Avant d’installer Spark, installez **Java**.

### Optimisation WSL (Windows)
Avant d’installer Java, modifiez le fichier `/etc/updatedb.conf` pour ajouter **/mnt** dans `PRUNEPATHS`. Sinon, l’indexation Windows ralentit fortement l’installation.
- Plus d’infos : https://askubuntu.com/questions/1251484/why-does-it-take-so-much-time-to-initialize-mlocate-database

### Installation Spark
Un tutoriel complet est disponible ici : https://computingforgeeks.com/how-to-install-apache-spark-on-ubuntu-debian/

### Réduire la verbosité Spark
Spark peut être très verbeux. Pour réduire les logs :
1. Aller dans `/opt/spark/conf`
2. Copier `log4j2.properties.template` → `log4j2.properties`
3. Modifier `rootLogger.level = info` → `rootLogger.level = error`

### Lancer un script Spark
Exemple :
```bash
/opt/spark/bin/spark-submit wordcount.py text.txt
```

## 2) Spark Shell
Pour lancer la version Python :
```bash
pyspark
# ou
/opt/spark/bin/pyspark
```

Pour un interpréteur plus convivial :
1. Installer **ipython** : `pip install ipython`
2. Définir `PYSPARK_PYTHON=ipython`
3. Lancer :
```bash
PYSPARK_PYTHON=ipython /opt/spark/bin/pyspark
# ou
PYSPARK_PYTHON=ipython pyspark
```

Dans un Spark Shell, le **SparkContext** est déjà créé et accessible via la variable `sc`.

## 3) Installation d’AWS CLI
### Installer AWS CLI v2
Documentation officielle : https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

Vérifier l’installation :
```bash
which aws
```

### (Optionnel) AWS CLI v1
Non recommandé :
```bash
pip install awscli
```

### Création d’une clé d’accès
Sur AWS : **Nom du compte → Informations d’identification de sécurité → Créer une clé d’accès**.
> ⚠️ Supprimez/désactivez la clé après usage.

### Configuration AWS CLI
```bash
aws configure
```
- **Access key ID** + **Secret access key**
- **Default region name** : `eu-west-3` (France)
- **Default output format** : laisser vide ou `json`

## 4) Création d’un bucket S3
Nous stockons : images, notebooks, logs Spark, sorties du pipeline.

Créer un bucket :
```bash
aws s3 mb s3://Nom_Du_Bucket
```
> Le nom doit être unique globalement (tous les comptes AWS).

### Upload de fichiers
```bash
aws s3 sync . s3://Nom_Du_Bucket/Nom_Du_Dossier_De_Destination
```

### Accès public (optionnel)
Pour partager certains fichiers :
1. Bucket → **Autorisation** → désactiver *Bloquer l’accès public* (avec prudence).
2. Définir une politique JSON, par exemple pour partager un notebook et un CSV :
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::Nom_Du_Bucket/jupyter/jovyan/P8_Notebook_Linux_EMR_PySpark_V1.0.ipynb"
    },
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::Nom_Du_Bucket/Results/pcaFeatures.csv"
    }
  ]
}
```

## 5) Création du cluster AWS EMR
Sur la console EMR :
- Créer un cluster
- Nommer le cluster
- Choisir la dernière version EMR
- Cocher **Hadoop**, **Spark**, **TensorFlow**, **JupyterHub**

### Configuration du cluster
- Type d’instance : `m5a.xlarge` (compatible région Paris)
- 1 instance maître + 2 workers (pas de groupe de tâches)

### Réseaux
Choisir le VPC et sous‑réseau correspondant à votre bucket S3.

### Résiliation automatique
Activer la résiliation automatique après inactivité (évite des coûts inutiles).

### Bootstrap (dépendances)
Les actions d’amorçage installent les dépendances nécessaires. Exemple **réel du projet** (voir `bootstrap.sh`) :
```bash
#!/bin/bash
# Upgrade core tooling (stable for Python 3.9 / EMR)
sudo python3 -m pip install --upgrade "pip<24" setuptools wheel

# Numeric stack (PINNED)
sudo python3 -m pip install --no-cache-dir \
    numpy==1.26.4 \
    pandas==1.5.3 \
    pyarrow==14.0.2

# TensorFlow stack (CPU, compatible)
sudo python3 -m pip install --no-cache-dir \
    ml-dtypes==0.2.0 \
    tensorflow==2.15.0

# Imaging
sudo python3 -m pip install pillow

# AWS / IO
sudo python3 -m pip install \
    boto3 \
    s3fs \
    fsspec
```

### Logs du cluster
Définir un chemin S3 pour conserver les logs Spark après résiliation.

### Persistance JupyterHub
Pour ne pas perdre les notebooks :
```json
[
  {
    "Classification": "jupyter-s3-conf",
    "Properties": {
      "s3.persistence.bucket": "Nom_Du_Bucket",
      "s3.persistence.enabled": "true"
    }
  }
]
```

### Sécurité / IAM / clés EC2
- Créer une paire de clés EC2 (fichier `.pem`).
- Choisir/Créer les rôles IAM nécessaires.

## 6) Connexion au master (driver) et accès JupyterHub
### Ouvrir le port SSH (22)
Dans EC2 → Groupe de sécurité `ElasticMapReduce-master` → ouvrir le port **22** (IPv4/IPv6).

### Connexion SSH
```bash
ssh -i Nom_Clef_EC2.pem hadoop@DNS_public_du_noeud_primaire
```
- Le fichier `.pem` doit avoir des droits restrictifs :
  - Linux : `chmod 600 Nom_Clef_EC2.pem`

### Tunnel SSH (proxy)
```bash
ssh -i Nom_Clef_EC2.pem -D 5555 hadoop@DNS_public_du_noeud_primaire
```
Configurer un proxy **SOCKS5** sur `localhost:5555` (ex. extension FoxyProxy).

### Accès JupyterHub
Dans l’onglet **Application** du cluster, ouvrir **JupyterHub**.
Identifiants par défaut :
- login : `jovyan`
- password : `jupyter`

Uploader le notebook EMR et sélectionner le kernel **pyspark**.

---

# Exécution des notebooks
## Local
1. Ouvrir `notebook/P8_Notebook_Linux_PySpark_Local_V1.0.ipynb`
2. Lancer les cellules dans l’ordre :
   - chargement des images
   - extraction des features (MobileNetV2)
   - PCA + export

## EMR
1. Ouvrir `notebook/P8_Notebook_Linux_EMR_PySpark_V1.0.ipynb`
2. Adapter les chemins S3 si nécessaire
3. Lancer le pipeline distribué

---

# Résultats produits
- **Fichiers Parquet** avec features et composantes PCA.
- **CSV** avec `filename`, `label`, `pcaFeatures` pour exploitation downstream (classification, indexation, etc.).

---

Si vous souhaitez répliquer le projet : commencez en local, validez le pipeline, puis migrez vers EMR en utilisant le bootstrap et la configuration S3.
