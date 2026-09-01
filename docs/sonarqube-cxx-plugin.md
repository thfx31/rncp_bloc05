# SonarQube - plugin C/C++ (sonar-cxx)

## Contexte

SonarQube Community Edition ne supporte pas nativement l'analyse C/C++/Objective-C
(le CFamily officiel est réservé à Developer Edition). Sans plugin, une analyse
sur `app/firmware-poc` (code C) remonte "0 lignes de code" - le scanner envoie
bien les fichiers mais aucun analyseur de langage ne les traite.

Solution retenue pour ce POC : installer le plugin communautaire
[sonar-cxx](https://github.com/SonarOpenCommunity/sonar-cxx) à la main sur le
pod SonarQube. **Ce n'est pas géré par le Helm chart** (`kubernetes/01-apps/sonarqube-app.yaml`)
- le jar est copié directement sur le volume persistant du pod. Ces étapes sont
donc à rejouer manuellement après un destroy/rebuild du cluster (cf.
[`rebuild-runbook.md`](rebuild-runbook.md)).

## 1. Installer le plugin

Vérifier la version Java du pod (le plugin exige Java 21+) :

```bash
export KUBECONFIG=$HOME/.kube/config-rncp-bc05
kubectl exec -n sonarqube sonarqube-sonarqube-0 -- java -version
```

Télécharger le jar du plugin (uniquement `sonar-cxx-plugin-*.jar`, **pas**
`cxx-sslr-toolkit-*.jar` qui n'est pas un plugin et fait planter le serveur au
démarrage s'il est déposé dans `plugins/`) - vérifier la
[page des releases](https://github.com/SonarOpenCommunity/sonar-cxx/releases)
pour la version compatible avec la version de SonarQube déployée (cf. la
section "SonarQube compatibility" de chaque release) :

```bash
curl -L -o sonar-cxx-plugin-2.3.0.1496.jar \
  https://github.com/SonarOpenCommunity/sonar-cxx/releases/download/cxx-2.3.0/sonar-cxx-plugin-2.3.0.1496.jar
```

Copier le jar dans le pod (le dossier `extensions/plugins` n'existe pas par
défaut, il faut le créer) puis redémarrer pour que le plugin soit chargé :

```bash
kubectl exec -n sonarqube sonarqube-sonarqube-0 -- mkdir -p /opt/sonarqube/extensions/plugins

kubectl cp sonar-cxx-plugin-2.3.0.1496.jar \
  sonarqube/sonarqube-sonarqube-0:/opt/sonarqube/extensions/plugins/sonar-cxx-plugin-2.3.0.1496.jar

kubectl rollout restart statefulset sonarqube-sonarqube -n sonarqube
kubectl rollout status statefulset sonarqube-sonarqube -n sonarqube
```

Vérifier le chargement dans les logs (ligne `Deploy C++ (Community) / ...`) :

```bash
kubectl logs -n sonarqube sonarqube-sonarqube-0 | grep -i "C++ (Community)"
```

Le pod met 1-2 minutes à redevenir `1/1 Ready` (migration DB + réenregistrement
des règles). Attendre avant de continuer.

## 2. Activer un profil qualité pour le langage CXX

Le profil built-in **"Sonar way"** (langage `CXX`) est livré **sans aucune
règle active** et il est en lecture seule (impossible d'activer des règles
dessus directement).

1. *Quality Profiles* → filtrer sur langage **CXX** → ouvrir **Sonar way**.
2. Menu **⋮** → **Copy** → nommer la copie, ex. `sonar-way - PoC`.
3. Sur cette copie (éditable) : **Activate More Rules**, filtrer par
   **Software Quality = Reliability + Security + Maintainability**, activer en
   masse (Bulk Change). Ne pas se limiter aux sévérités Blocker/High/Medium :
   le volume réel de findings est de toute façon borné par ce que l'outil
   d'analyse (cppcheck, capteur natif du plugin) détecte sur un petit projet,
   pas par la taille du catalogue de règles.
4. Menu **⋮** de la copie → **Set as Default** (pour le langage CXX).

Sans cette étape, une analyse tourne, compte les lignes de code, mais
n'affiche jamais aucune issue (les violations sont calculées côté scanner puis
silencieusement écartées si aucune règle active ne correspond).

## 3. Quality Gate - éviter de bloquer le pipeline

Le gate par défaut ("Sonar way") échoue systématiquement sur ce projet :
- `Coverage < 80%` - aucun outil de couverture n'est branché pour le C ici.
- `New Issues > 0` - le profil CXX complet remonte des dizaines de règles de
  convention (ex. "Undocumented API") sur un projet qui n'a pas ce niveau de
  documentation - normal pour un POC, pas un vrai defect.

Pour avoir un rapport visible sans faire échouer le pipeline Jenkins
(`sonar.qualitygate.wait=true` dans le `Jenkinsfile`) :

1. *Quality Gates* → **Create**, nommer par ex. `PoC - report only`.
2. Supprimer les conditions **Issues** et **Coverage** (icône poubelle). Garder
   le reste (Security Hotspots Reviewed, Duplicated Lines) - elles ne posent
   pas de problème sur ce projet.
3. **Ne pas** cliquer sur la bannière "Review and update" / "standards
   recommandés par Sonar" qui réintroduirait des conditions strictes.
4. Menu **⋮** → **Set as Default** (s'applique à tous les projets de
   l'instance, y compris `firmware-poc-modern` dès sa première analyse - pas
   besoin de l'assigner projet par projet).

## Résumé rejouable après un rebuild

1. Installer le plugin (§1) - même version de plugin si la version de
   SonarQube déployée n'a pas changé (vérifier la compatibilité sinon).
2. Copier/activer le profil CXX (§2), le mettre en Default.
3. Créer et assigner le Quality Gate `PoC - report only` (§3).

Le reste (stage cppcheck du Jenkinsfile, propriétés `sonar.cxx.*`) est dans le
code versionné et n'a pas besoin d'être refait à la main.
