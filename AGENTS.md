# AGENTS.md

## Mission générale

Ce dépôt contient la logique d’un système de supervision fusion en Lua.
Toute intervention doit préserver la stabilité du runtime, la compatibilité avec l’installateur et le système d’update par manifeste.

## Règles globales

- Toujours respecter l’architecture existante du dépôt.
- Ne pas remplacer un système fonctionnel par une réécriture totale sans nécessité.
- Préférer l’extraction, la modularisation et la réutilisation à la duplication.
- Ne pas hardcoder un unique setup terrain.
- Conserver une logique permissive et tolérante aux périphériques différents.
- Ne jamais dégrader la robustesse actuelle pour améliorer uniquement l’esthétique.
- Toute modification runtime doit rester compatible avec l’update par manifeste.
- Toujours incrémenter `fusion.version` avec une version strictement supérieure si des fichiers runtime changent.
- Toujours synchroniser `fusion.manifest.json` avec les fichiers runtime réellement nécessaires.
- Adapter `install.lua` si de nouveaux fichiers doivent être installés.

## Langue et style

- Réponses et résumés en français.
- Code, commentaires de code, identifiants techniques, noms de fonctions et noms de fichiers en anglais.
- Garder un style de code cohérent avec le dépôt.

## Règles spécifiques Tom's Peripherals

Pour tout travail touchant l’interface Tom’s Peripherals fusion :

- Considérer la base runtime actuellement validée comme stable et réutilisable.
- Ne pas réinventer une nouvelle logique GPU/runtime si l’existante fonctionne déjà.
- La refonte doit partir de la base fonctionnelle validée, pas la jeter.
- La couche UI doit être séparée de la couche runtime.
- Ne pas continuer à empiler des coordonnées fixes dispersées dans le rendu.
- Construire l’UI avec :
  - un design system,
  - un layout engine,
  - des composants UI réutilisables,
  - un écran final composé proprement.
- L’interface doit rester belle, lisible et cohérente quelle que soit la taille réelle du GPU.
- Le style visuel recherché est :
  - industriel,
  - SCADA,
  - supervision technique,
  - futuriste sobre,
  - propre et lisible.
- Éviter les rectangles placeholders sans signification.
- Chaque zone affichée doit avoir un rôle clair.
- Les couleurs doivent avoir un sens :
  - bleu = information,
  - vert = ok / prêt,
  - orange = attention,
  - rouge = critique / arrêt.
- Le cœur visuel du panneau doit être le réacteur, pas une accumulation de blocs décoratifs.

## Base technique à préserver

La base technique validée doit être conservée ou réutilisée autant que possible, notamment :

### Détection et sélection périphériques

- `getNames()`
- `getMethods()`
- `methodSet()`
- `hasAll()`
- `wrapIf()`
- `exists()`
- `filterAliases()`
- `pickPreferred()`
- `chooseOne()`
- `findGpus()`
- `findKeyboards()`
- `findRsports()`
- `findByExistingNames()`

### Initialisation GPU

Après sélection du GPU :

1. `refreshSize()`
2. tentative `pcall(gpu.setSize, 64)`
3. `refreshSize()`
4. `getSize()`

Toujours utiliser la taille runtime réelle renvoyée par `getSize()`.

### Lecture runtime / fallbacks

- `hasMethod()`
- `tryCall()`
- `fmt()`
- `clamp()`
- lecture permissive des données fusion / laser

### Sécurités runtime

- `allow_control = false` par défaut
- aucun ordre critique si `allow_control` est désactivé
- aucun crash si une méthode manque
- conserver la logique de `pulseLaser()` et `changeInjection()` ou un équivalent mieux structuré

### Sécurités graphiques

- `clipText()`
- `safeFilledRect()`
- `safeRect()`
- `safeText()`

Ne jamais revenir à un rendu susceptible de provoquer des erreurs hors bornes.

### Interactions

- conserver la compatibilité avec :
  - `tm_monitor_touch`
  - `tm_monitor_mouse_click`
  - boucle timer + redraw
  - événements clavier utiles
- le hit-testing doit rester fiable même après refonte

## Architecture UI attendue

Pour toute refonte UI Tom’s, viser une structure du type :

- thème / design tokens
- layout engine
- composants UI
- écran fusion Tom’s
- orchestration légère

Les noms exacts peuvent varier selon l’architecture du dépôt, mais la séparation des responsabilités doit être claire.

## Windows Tom’s Peripherals

L’usage de `createWindow(...)` est autorisé et recommandé si cela améliore réellement la structure.

Règles :
- ne pas multiplier inutilement les windows,
- éviter le gaspillage VRAM,
- garder un ordre de sync clair,
- conserver un fond root GPU propre,
- ne jamais dépendre d’une seule taille d’écran.

## Refactor complexe

Pour toute refonte UI importante :

- créer et suivre un plan d’exécution dans `PLANS.md`,
- ne pas “bricoler” l’ancien rendu par petites retouches successives si cela empêche une architecture propre,
- séparer clairement :
  - ce qui fonctionne déjà et doit être conservé,
  - ce qui est visuellement insuffisant et doit être refondu.

## Critères de qualité

Une refonte UI Tom’s est acceptable seulement si :

- la base technique validée est préservée,
- la nouvelle UI est réellement plus propre,
- l’interface reste robuste sur différentes tailles,
- aucune erreur graphique hors bornes n’est possible,
- les données critiques restent toujours visibles,
- les contrôles restent utilisables,
- la structure est maintenable,
- `fusion.version` et `fusion.manifest.json` sont cohérents.
