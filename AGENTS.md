# AGENTS.md

## Workflow obligatoire pour toute itération Codex sur fusion-vipercraft

Tu travailles sur le dépôt GitHub suivant :
https://github.com/viper1331/fusion-vipercraft.git

### Règles générales

- Toujours commencer par récupérer l’état le plus récent du dépôt distant avant toute modification.
- Vérifier l’état Git local avant toute opération.
- Ne jamais écraser silencieusement des changements locaux non commités.
- Si des changements locaux existent, les signaler explicitement et proposer la stratégie la plus sûre :
  - commit préalable,
  - stash,
  - ou arrêt avec explication claire.
- Toujours travailler de façon compatible avec l’architecture actuelle du dépôt.
- Toujours préserver les fonctionnalités déjà validées, sauf demande explicite de remplacement.

### Synchronisation dépôt

Au début de chaque itération :
1. vérifier la branche courante ;
2. récupérer la dernière version du dépôt distant ;
3. mettre à jour proprement la branche de travail ;
4. confirmer dans le compte rendu quelle révision ou quel état distant a été utilisé.

Si un pull ou rebase échoue :
- ne pas forcer ;
- expliquer précisément le blocage ;
- proposer la correction la plus sûre.

### Versionning obligatoire à chaque itération utile

À chaque itération qui modifie le runtime, l’installateur, le manifeste, l’UI, le backend, ou tout comportement fonctionnel du programme :
- incrémenter `fusion.version` avec une version strictement supérieure ;
- mettre à jour `fusion.manifest.json` pour inclure tous les fichiers nécessaires réellement utilisés au runtime ;
- revoir `install.lua` et le modifier si nécessaire pour prendre en charge les nouveaux fichiers, modules, dépendances, assets, logs, scripts ou comportements installables.

Ne jamais oublier ces trois fichiers :
- `fusion.version`
- `fusion.manifest.json`
- `install.lua`

Même si `install.lua` ne change pas, le vérifier explicitement à chaque itération importante et l’indiquer dans le compte rendu.

### Règle spécifique sur install.lua

À chaque demande de nouvelle fonction, nouvelle UI, nouveau module, nouveau fichier de configuration, nouveau fichier de log, nouveau backend ou nouveau composant technique :
- évaluer si `install.lua` doit être adapté ;
- si oui, le modifier dans la même itération ;
- si oui, incrémenter `install.lua` avec une version strictement supérieure ;
- si non, l’indiquer explicitement dans le débrief avec la raison.

### Git obligatoire en fin d’itération

À la fin de chaque itération terminée et cohérente :
- vérifier les fichiers modifiés ;
- faire un commit avec un message clair et professionnel ;
- pousser les changements sur le dépôt distant.

Ne pas laisser une itération importante non commitée si elle est considérée comme terminée.

Si le push échoue :
- expliquer précisément pourquoi ;
- ne pas prétendre que le travail est publié ;
- indiquer l’état Git exact restant local.

### Qualité de commit attendue

Les commits doivent :
- être explicites ;
- refléter le vrai contenu de l’itération ;
- éviter les messages vagues comme "update", "fix stuff", "misc".

Préférer des messages du type :
- `Refactor Tom's native UI backend selection`
- `Add native Tom debug logging and manifest sync`
- `Update installer for new Tom UI modules`

### Compte rendu obligatoire en français

Après chaque itération, fournir un débrief détaillé en français, clair et structuré, avec au minimum :

1. objectif de l’itération ;
2. fichiers modifiés ;
3. fichiers créés ;
4. fichiers supprimés ;
5. logique fonctionnelle modifiée ;
6. impacts techniques ;
7. backend ou UI concernés ;
8. adaptations éventuelles de `install.lua` ;
9. mise à jour de `fusion.manifest.json` ;
10. nouvelle version inscrite dans `fusion.version` ;
11. état du commit ;
12. état du push ;
13. éventuels risques, limites ou points à tester ;
14. tests manuels recommandés.

### Règles de sécurité et robustesse

- Ne jamais annoncer qu’une fonctionnalité est opérationnelle sans avoir vérifié le minimum pertinent.
- Ne jamais casser la compatibilité terrain si le projet supporte plusieurs backends ou plusieurs types de moniteurs.
- Toujours préserver la coexistence entre l’interface classique et l’interface Tom si le dépôt les supporte.
- Toujours privilégier la détection terrain réelle plutôt qu’un hardcode fragile.
- Toujours conserver les garde-fous existants, notamment les sécurités runtime comme `allow_control = false` par défaut si elles existent déjà.
- Ne pas faire de simplification destructrice juste pour réduire le code.

### Règles d’analyse avant codage

Avant toute modification significative :
- relire les fichiers déjà impliqués ;
- identifier les modules liés ;
- éviter les duplications ;
- réutiliser l’existant si la base est valide.

Pour les tâches complexes ou multi-fichiers :
- faire d’abord un mini plan ;
- puis exécuter ;
- puis résumer ce qui a réellement été fait.

### Politique sur les régressions

Toute itération doit chercher explicitement à éviter :
- régression d’affichage ;
- régression de backend ;
- oubli de manifeste ;
- oubli d’installateur ;
- oubli de version ;
- oubli de push ;
- perte de compatibilité classique/Tom ;
- écrasement involontaire de changements existants.

### Définition de “travail terminé”

Une itération est considérée terminée seulement si :
- les changements de code sont appliqués ;
- `fusion.version` est incrémenté si nécessaire ;
- `fusion.manifest.json` est synchronisé si nécessaire ;
- `install.lua` a été vérifié et adapté si nécessaire ;
- le débrief en français est fourni ;
- le commit est fait ;
- le push est tenté et son résultat est clairement indiqué.

### Priorité absolue

En cas de doute :
1. préserver le dépôt ;
2. préserver la compatibilité terrain ;
3. préserver la cohérence version/manifeste/install ;
4. documenter clairement ;
5. commit/push proprement.

## Plan obligatoire pour les tâches complexes

Si la tâche touche plusieurs modules, plusieurs backends, l’UI, le runtime, l’installateur ou le manifeste :
- faire un plan court avant de coder ;
- exécuter le plan ;
- signaler les écarts entre le plan et le résultat final.

## Complément spécifique CraftOS-PC pour les tests Codex

CraftOS-PC n’est utilisé ici que comme environnement de test local du programme par Codex.

Règles obligatoires :
- pour tout test local du programme via CraftOS-PC sous Windows, utiliser obligatoirement `CraftOS-PC_console.exe` et non `CraftOS-PC.exe` ;
- cette obligation ne concerne que les scripts, outils, tâches, batchs ou configurations utilisés par Codex pour exécuter ou tester le programme dans CraftOS-PC ;
- ne pas modifier les autres points de lancement du projet si CraftOS-PC n’est pas leur runtime réel ;
- vérifier explicitement la présence de `CraftOS-PC_console.exe` avant de conclure qu’un environnement de test CraftOS-PC est opérationnel ;
- si `CraftOS-PC_console.exe` est absent, arrêter la mise en place du test CraftOS-PC et indiquer clairement qu’il faut relancer l’installateur CraftOS-PC avec l’option `Console build` activée ;
- si un chemin vers CraftOS-PC existe déjà dans la configuration de test, le réutiliser et le corriger vers la version console au lieu d’écrire un chemin en dur ;
- mettre à jour tous les scripts de test, batchs, tâches VS Code ou configurations utilisées par Codex pour qu’ils pointent vers `CraftOS-PC_console.exe` ;
- ne jamais considérer un test CraftOS-PC comme valide si le point de lancement utilisé par Codex référence encore `CraftOS-PC.exe` au lieu de `CraftOS-PC_console.exe`.

Compte rendu attendu si CraftOS-PC est concerné :
- préciser que CraftOS-PC est utilisé uniquement pour les tests locaux ;
- indiquer quel exécutable de test est utilisé ;
- indiquer quels scripts ou configurations de test ont été corrigés ;
- préciser si la build console a été vérifiée ou non.

