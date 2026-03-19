# PLANS.md

## ExecPlan — Refonte complète de l'interface Tom's Peripherals fusion

### Statut

Plan actif.

### Décision

La refonte de l’interface Tom’s Peripherals doit être faite en s’appuyant explicitement sur la base technique déjà validée.
La logique runtime existante n’est pas à jeter.
La refonte doit porter principalement sur :

- l’architecture UI,
- le design system,
- le layout,
- les composants,
- la composition visuelle finale.

### Base technique de référence à conserver

Le système actuellement validé sert de socle technique.
Il doit être conservé, réutilisé ou extrait proprement dans des modules plus clairs.

Éléments à conserver ou réutiliser autant que possible :

#### Détection périphériques

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

#### Initialisation GPU

- wrap GPU
- `refreshSize()`
- `pcall(gpu.setSize, 64)`
- `refreshSize()`
- `getSize()`

#### Lecture des données

- `hasMethod()`
- `tryCall()`
- `fmt()`
- `clamp()`
- lecture permissive des méthodes fusion / laser

#### Sécurités runtime

- `allow_control = false` par défaut
- `pulseLaser()`
- `changeInjection()`
- aucun crash si méthode absente

#### Sécurités graphiques

- `clipText()`
- `safeFilledRect()`
- `safeRect()`
- `safeText()`

#### Interactions

- boutons
- `handleClick()`
- `tm_monitor_touch`
- `tm_monitor_mouse_click`
- boucle timer + redraw
- raccourcis clavier utiles

---

## Objectif final

Produire une nouvelle interface Tom’s :

- propre,
- lisible,
- élégante,
- cohérente,
- adaptive,
- robuste,
- professionnelle,
- belle quelle que soit la taille réelle du GPU.

Le style visé est :

- supervision industrielle,
- SCADA,
- salle de contrôle,
- futuriste sobre.

---

## Contraintes

- Ne pas repartir d’une nouvelle logique runtime.
- Ne pas perdre la permissivité actuelle.
- Ne pas hardcoder un seul setup matériel.
- Ne pas réintroduire de coordonnées magiques non protégées.
- Ne pas produire une “jolie interface” fragile.
- Ne pas casser l’installateur.
- Ne pas casser le système d’update par manifeste.

---

## Architecture cible

La couche UI Tom’s doit être restructurée en composants clairs.

Architecture souhaitée, à adapter au style du repo si nécessaire :

- `ui/toms/theme.lua`
- `ui/toms/layout.lua`
- `ui/toms/components.lua`
- `ui/toms/fusion_screen.lua`

Ou toute structure équivalente respectant la séparation suivante :

1. thème / design tokens
2. layout engine
3. composants UI
4. écran final
5. orchestration / branchement runtime

---

## Phases d’exécution

### Phase 1 — Inspection du dépôt

Identifier précisément :

- le point d’entrée principal,
- les fichiers UI Tom’s actuels,
- les helpers déjà présents,
- les modules réutilisables dans `core/`, `io/`, `ui/`,
- les chemins impactés par le manifeste et l’installation.

Décider ce qui est :

- conservé,
- extrait,
- remplacé,
- supprimé.

### Phase 2 — Extraction de la base technique

À partir du système validé :

- isoler proprement la logique périphériques/runtime,
- éviter la duplication,
- garder un point d’orchestration clair,
- séparer la logique technique de la logique visuelle.

Objectif :
avoir une base stable sur laquelle brancher la nouvelle UI.

### Phase 3 — Création du design system

Créer une couche de style centralisée.

Prévoir au minimum :

#### Palette

- info blue
- ok green
- warning orange
- critical red
- dark panel background
- secondary panel background
- primary text
- muted text
- border colors
- accent colors

#### Échelle d’espacement

- outer margin
- panel padding
- panel gap
- section gap
- line spacing

#### Échelle de taille

- title height
- subtitle height
- row height
- gauge thickness
- button height
- badge height

#### Règles de texte

- clipping
- truncation
- alignment
- centering si nécessaire

Toutes les tailles doivent être dérivées d’une échelle UI calculée depuis `W` et `H`.

### Phase 4 — Création du layout engine

Construire un moteur de layout calculé depuis la taille runtime réelle.

Structure recommandée :

- root bounds
- header
- content
- footer

Dans `content`, calculer dynamiquement :

- reactor summary
- temperatures
- laser / power
- reactor core
- status / debug
- controls si utile selon la densité

Prévoir 3 niveaux de densité :

- small density
- medium density
- large density

Important :
ce n’est pas 3 interfaces différentes.
C’est la même identité visuelle, avec plus ou moins de richesse selon la place disponible.

### Phase 5 — Création des composants UI

Créer des composants cohérents et réutilisables.

Au minimum :

- `drawPanel`
- `drawPanelHeader`
- `drawSectionTitle`
- `drawLabelValue`
- `drawStatusBadge`
- `drawGauge`
- `drawHorizontalBar`
- `drawVerticalBar`
- `drawButton`
- `drawButtonRow`
- `drawReactorCore`
- `drawHeader`
- `drawFooter`

Règles :

- jamais de dessin hors zone,
- clipping/truncation obligatoire,
- style homogène,
- réutilisables sur plusieurs tailles.

### Phase 6 — Nouvelle composition de l’écran

Composer le nouvel écran fusion à partir :

- du layout engine,
- des composants,
- des données runtime,
- de la base technique existante.

Sections attendues :

#### Header
- titre global
- nom GPU
- état système global

#### Reactor summary
- active / ignited
- injection
- passive generation
- steam
- fuel si disponible

#### Temperatures
- plasma temp
- case temp
- target ignition

#### Laser / Power
- energy
- max
- ratio
- état prêt / non prêt si pertinent

#### Reactor core
- représentation stylisée du réacteur
- centré
- adaptable
- visuellement utile
- pas un placeholder

#### Status / Debug
- erreur en cours
- périphériques réellement utilisés
- méthodes matchées si utile
- mode contrôle

#### Footer / Controls
- Refresh
- Laser Pulse
- Injection -
- Injection +
- Quit

### Phase 7 — Utilisation éventuelle des windows Tom’s

Utiliser `createWindow(...)` seulement si cela améliore clairement :

- la structure,
- la lisibilité,
- la modularité,
- le rendu.

Règles :

- nombre raisonnable de windows,
- pas de gaspillage VRAM,
- fond root GPU conservé,
- ordre de sync explicite.

### Phase 8 — Finalisation visuelle

L’interface finale ne doit plus ressembler :

- ni à une accumulation de rectangles,
- ni à un prototype,
- ni à un layout placeholder.

Attendus :

- hiérarchie visuelle claire,
- panneaux équilibrés,
- espacement régulier,
- titres lisibles,
- valeurs bien alignées,
- jauges identifiables,
- centre réacteur valorisé,
- style sobre et professionnel.

### Phase 9 — Nettoyage

Une fois la nouvelle UI en place :

- retirer l’ancienne couche UI Tom’s devenue obsolète,
- éviter les doubles chemins de rendu,
- laisser un code maintenable.

### Phase 10 — Intégration dépôt

Mettre à jour si nécessaire :

- `fusion.version`
- `fusion.manifest.json`
- `install.lua`

S’assurer qu’aucun fichier runtime nécessaire n’est oublié.

---

## Données critiques toujours visibles

Quelle que soit la taille, l’UI doit toujours afficher :

- état réacteur,
- injection,
- plasma temp,
- case temp,
- énergie laser,
- statut global / erreur.

Si une donnée manque :

- afficher `N/A` proprement,
- ne jamais laisser une zone vide sans explication.

---

## Interactions

Le hit-testing doit être recalculé depuis le layout, pas codé avec des coordonnées figées.

Compatibilité à préserver :

- `tm_monitor_touch`
- `tm_monitor_mouse_click`
- timer refresh
- raccourcis clavier utiles

Les boutons doivent rester :

- visibles,
- bien espacés,
- lisibles,
- exploitables quelle que soit la taille.

---

## Critères d’acceptation

La refonte est considérée terminée seulement si :

1. la base technique validée est conservée comme socle ;
2. la couche UI actuelle a bien été remplacée ;
3. l’interface est visuellement propre et professionnelle ;
4. l’interface reste belle sur petit, moyen et grand écran ;
5. aucune erreur graphique hors bornes n’est possible ;
6. les données critiques restent visibles ;
7. le réacteur central a un vrai rôle visuel ;
8. les contrôles restent utilisables ;
9. la détection périphérique reste permissive ;
10. `fusion.version` a été incrémenté ;
11. `fusion.manifest.json` a été synchronisé ;
12. `install.lua` reste compatible.

---

## Livrables attendus de l’implémentation

1. liste exacte des fichiers modifiés ;
2. liste exacte des fichiers créés ;
3. résumé clair en français ;
4. explication de ce qui a été conservé depuis la base validée ;
5. explication de ce qui a été refondu ;
6. description du design system ;
7. description du layout engine ;
8. description des composants créés ;
9. description des états visuels du reactor core ;
10. description du comportement small / medium / large density ;
11. confirmation que la refonte repose bien sur le système validé ;
12. tests manuels recommandés en jeu.
