# PLANS.md

## ExecPlan — Refonte UI Tom's Peripherals sur backend natif validé

### Statut

Plan actif.

### Décision

La refonte de l’interface Tom’s Peripherals doit désormais être menée sur une base technique validée :

- le backend Tom natif est fonctionnel ;
- la sélection automatique de backend terrain doit être conservée ;
- la coexistence entre interface classique et interface Tom doit être maintenue ;
- la refonte doit maintenant porter principalement sur la qualité visuelle, la structure UI, le design system, le layout, les composants et la composition finale.

### Nouveau diagnostic validé

Les derniers diagnostics ont confirmé que :

- le bon GPU Tom est détecté ;
- le backend `toms_gpu` / `toms_native` est opérationnel ;
- le runtime source natif Tom est correctement utilisé ;
- les dimensions runtime natives sont correctement conservées ;
- le mode debug Tom utilise le même pipeline natif que la production ;
- le gros problème de wrapper monitor parasite est résolu.

En conséquence :

- il ne faut plus refaire l’architecture backend Tom ;
- il ne faut plus rebasculer vers une abstraction monitor pour l’UI Tom ;
- la priorité est maintenant la refonte visuelle et structurelle de l’interface Tom sur cette base saine ;
- seule une correction ciblée des métriques/logs incohérents reste autorisée côté backend/debug.

---

## Contraintes non négociables

- Ne pas casser la coexistence entre interface classique et interface Tom.
- Ne pas supprimer le support des moniteurs classiques.
- Ne pas supprimer le support natif Tom’s GPU.
- Le programme doit continuer à s’adapter automatiquement au terrain :
  - UI classique si terrain classique,
  - UI Tom native si GPU Tom valide.
- Ne pas repartir d’une nouvelle logique runtime.
- Ne pas toucher au pipeline natif Tom validé, sauf pour corriger des logs/métriques debug incorrects.
- Ne pas perdre la permissivité actuelle.
- Ne pas hardcoder un seul setup matériel.
- Ne pas réintroduire de coordonnées magiques non protégées.
- Ne pas produire une “jolie interface” fragile.
- Ne pas casser l’installateur.
- Ne pas casser le système d’update par manifeste.

---

## Base technique de référence à conserver

Le système validé sert de socle technique.
Il doit être conservé, réutilisé ou extrait proprement dans des modules plus clairs.

### Détection et sélection backend

Conserver ou réutiliser autant que possible :

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

#### Sélection de backend terrain
Le programme doit continuer à distinguer au minimum :
- `classic_monitor`
- `toms_native`
- `terminal_fallback` si nécessaire

### Initialisation GPU Tom native

Conserver la séquence validée :
- wrap GPU
- `refreshSize()`
- `pcall(gpu.setSize, 64)`
- `refreshSize()`
- `getSize()`

### Lecture des données
- `hasMethod()`
- `tryCall()`
- `fmt()`
- `clamp()`
- lecture permissive des méthodes fusion / laser

### Sécurités runtime
- `allow_control = false` par défaut
- `pulseLaser()`
- `changeInjection()`
- aucun crash si méthode absente

### Sécurités graphiques
- `clipText()`
- `safeFilledRect()`
- `safeRect()`
- `safeText()`

### Interactions
- boutons
- `handleClick()`
- `tm_monitor_touch`
- `tm_monitor_mouse_click`
- boucle timer + redraw
- raccourcis clavier utiles

### Debug Tom
Le mode debug Tom doit rester sur le même chemin natif que la prod Tom.
Il ne doit pas rebasculer vers un wrapper monitor.

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
- belle quelle que soit la taille réelle du GPU natif,
- immédiatement compréhensible comme un panneau de supervision.

Le style visé est :

- supervision industrielle,
- SCADA,
- salle de contrôle,
- futuriste sobre.

---

## Architecture cible

La couche UI Tom’s doit rester structurée en composants clairs.

Architecture souhaitée, à adapter au style du repo si nécessaire :

- `ui/toms/theme.lua`
- `ui/toms/layout.lua`
- `ui/toms/components.lua`
- `ui/toms/fusion_panel.lua`

Ou toute structure équivalente respectant la séparation suivante :

1. thème / design tokens
2. layout engine
3. composants UI
4. écran final
5. orchestration / branchement runtime

Important :
- conserver cette modularité ;
- ne pas revenir à un gros fichier de rendu monolithique ;
- ne pas refaire le backend de surface si celui-ci est déjà validé.

---

## Phases d’exécution

### Phase 1 — Validation des invariants backend

Avant tout travail visuel :

- vérifier que le backend Tom natif reste inchangé ;
- vérifier que l’UI classique reste disponible ;
- vérifier que la sélection automatique terrain reste disponible ;
- vérifier que le debug Tom continue à utiliser le même wrapper natif que la prod Tom.

À ce stade :
- ne pas réécrire le backend ;
- seulement corriger d’éventuelles incohérences de logging.

### Phase 2 — Correction des logs et métriques debug

Corriger les incohérences restantes dans le debug, notamment :

- valeurs `blocks`
- valeurs `wrapped`
- valeurs `scale`
- ou toute métrique mal étiquetée qui ne reflète pas correctement la réalité native du GPU

Objectif :
avoir un fichier debug fiable, cohérent, lisible, et utilisable pour les prochains diagnostics.

### Phase 3 — Inspection UI actuelle

Identifier précisément :

- les fichiers UI Tom actuels ;
- les helpers déjà présents ;
- les modules réutilisables dans `core/`, `io/`, `ui/` ;
- ce qui est déjà bon visuellement ;
- ce qui est placeholder ;
- ce qui doit être remplacé dans la composition.

Décider ce qui est :
- conservé,
- amélioré,
- refactoré,
- supprimé.

### Phase 4 — Consolidation du design system

Créer ou améliorer une couche de style centralisée.

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

### Phase 5 — Refonte du layout engine

Construire un moteur de layout calculé depuis la taille runtime réelle native.

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
ce ne sont pas 3 interfaces différentes.
C’est la même identité visuelle, avec plus ou moins de richesse selon la place disponible.

### Phase 6 — Refonte des composants UI

Créer ou améliorer des composants cohérents et réutilisables.

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

- jamais de dessin hors zone ;
- clipping/truncation obligatoire ;
- style homogène ;
- réutilisables sur plusieurs tailles ;
- aucune barre ou zone sans signification.

### Phase 7 — Nouvelle composition de l’écran Tom

Composer le nouvel écran fusion Tom à partir :

- du layout engine ;
- des composants ;
- des données runtime ;
- de la base technique existante.

Sections attendues :

#### Header
- titre global
- backend / GPU actif
- état système global

#### Reactor summary
- active / ignited
- injection
- passive generation
- steam ou `N/A`
- fuel si disponible

#### Temperatures
- plasma temp
- case temp
- target ignition

#### Laser / Power
- energy
- max
- ratio
- état prêt / non prêt

#### Reactor core
- représentation stylisée du réacteur
- centré
- adaptable
- visuellement utile
- pas un placeholder
- états visuels possibles :
  - idle
  - active
  - ready
  - warning
  - blocked si pertinent

#### Status / Debug
- erreur en cours ou raison du blocage
- backend utilisé
- wrapper utilisé
- méthodes matchées si utile
- mode contrôle

#### Footer / Controls
- Refresh
- Laser Pulse
- Injection -
- Injection +
- Quit

### Phase 8 — Usage éventuel des windows Tom’s

Utiliser `createWindow(...)` seulement si cela améliore clairement :

- la structure ;
- la lisibilité ;
- la modularité ;
- le rendu.

Règles :

- nombre raisonnable de windows ;
- pas de gaspillage VRAM ;
- fond root GPU conservé ;
- ordre de sync explicite ;
- aucune régression sur le rendu natif.

Si les windows n’apportent rien visuellement ou compliquent l’UI, préférer un rendu root GPU bien structuré.

### Phase 9 — Finalisation visuelle

L’interface finale ne doit plus ressembler :

- ni à une accumulation de rectangles ;
- ni à un prototype ;
- ni à un layout placeholder ;
- ni à une maquette abstraite.

Attendus :

- hiérarchie visuelle claire ;
- panneaux équilibrés ;
- espacement régulier ;
- titres lisibles ;
- valeurs bien alignées ;
- jauges identifiables ;
- centre réacteur valorisé ;
- footer de contrôle clair ;
- style sobre et professionnel.

### Phase 10 — Nettoyage

Une fois la nouvelle UI Tom en place :

- retirer l’ancienne couche visuelle Tom devenue obsolète ;
- éviter les doubles chemins de rendu Tom inutiles ;
- laisser un code maintenable ;
- conserver séparément l’UI classique.

### Phase 11 — Intégration dépôt

Mettre à jour si nécessaire :

- `fusion.version`
- `fusion.manifest.json`
- `install.lua`

S’assurer qu’aucun fichier runtime nécessaire n’est oublié.

---

## Données critiques toujours visibles

Quelle que soit la taille, l’UI Tom doit toujours afficher :

- état réacteur ;
- injection ;
- plasma temp ;
- case temp ;
- énergie laser ;
- statut global / erreur.

Si une donnée manque :

- afficher `N/A` proprement ;
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

- visibles ;
- bien espacés ;
- lisibles ;
- exploitables quelle que soit la taille.

---

## Compatibilité terrain obligatoire

Le programme doit continuer à supporter :

- l’interface classique pour les terrains en moniteur classique ;
- l’interface Tom native pour les terrains en GPU Tom.

Le choix doit continuer à se faire automatiquement selon la détection réelle du terrain.

La refonte UI Tom ne doit en aucun cas casser cette adaptation terrain.

---

## Critères d’acceptation

La refonte est considérée terminée seulement si :

1. le backend Tom natif validé est préservé ;
2. l’UI classique reste disponible ;
3. l’UI Tom reste disponible ;
4. la sélection automatique terrain reste fonctionnelle ;
5. la couche UI Tom actuelle a été réellement améliorée ;
6. l’interface Tom est visuellement propre et professionnelle ;
7. l’interface Tom reste belle sur petit, moyen et grand écran natif ;
8. aucune erreur graphique hors bornes n’est possible ;
9. les données critiques restent visibles ;
10. le réacteur central a un vrai rôle visuel ;
11. les contrôles restent utilisables ;
12. la détection périphérique reste permissive ;
13. le debug Tom reste sur le pipeline natif ;
14. le logging debug Tom est cohérent et fiable ;
15. `fusion.version` a été incrémenté ;
16. `fusion.manifest.json` a été synchronisé ;
17. `install.lua` reste compatible.

---

## Livrables attendus de l’implémentation

1. liste exacte des fichiers modifiés ;
2. liste exacte des fichiers créés ;
3. résumé clair en français ;
4. explication de ce qui a été conservé côté backend/runtime ;
5. explication de ce qui a été corrigé dans les logs debug ;
6. explication de ce qui a été refondu côté UI Tom ;
7. description du design system ;
8. description du layout engine ;
9. description des composants créés ou améliorés ;
10. description des états visuels du reactor core ;
11. description du comportement small / medium / large density ;
12. confirmation que l’UI classique reste disponible ;
13. confirmation que l’UI Tom reste disponible ;
14. confirmation que la sélection automatique terrain reste fonctionnelle ;
15. confirmation que la refonte UI Tom repose bien sur le backend natif validé ;
16. tests manuels recommandés en jeu.
