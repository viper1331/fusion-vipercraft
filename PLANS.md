# PLANS.md

## ExecPlan — Modularisation complète, centralisation et amélioration du code

### Statut

Plan actif.

### Décision

La séparation initiale des pages Tom a été poussée.  
La prochaine étape n’est plus une simple correction visuelle : il faut maintenant **finaliser proprement l’architecture**, **centraliser ce qui doit l’être**, **nettoyer le code mort**, **renforcer la cohérence native-pixel de l’UI Tom** et **améliorer globalement la maintenabilité du programme**.

---

## Objectif global

Faire évoluer le projet vers une architecture :

- plus modulaire ;
- plus claire ;
- plus maintenable ;
- plus cohérente entre UI classique et UI Tom ;
- plus robuste sur le terrain ;
- plus propre sur la gestion des pages, des composants, des assets, de la navigation et du runtime.

Le but n’est pas de réécrire gratuitement ce qui fonctionne déjà.  
Le but est de **consolider l’existant validé**, d’éliminer les zones techniques fragiles et de structurer proprement la suite du projet.

---

## Invariants à préserver

Les éléments suivants sont considérés comme **validés** et ne doivent pas être cassés :

1. **Backend Tom natif**
   - pipeline Tom natif validé ;
   - rendu natif GPU ;
   - dimensions runtime natives ;
   - compatibilité avec le debug Tom natif.

2. **Coexistence des interfaces**
   - interface classique disponible ;
   - interface Tom disponible ;
   - sélection automatique du backend selon la détection terrain.

3. **Comportements runtime**
   - adaptativité runtime ;
   - reflow à la volée ;
   - logique de navigation ;
   - logique de sécurité existante ;
   - `allow_control = false` par défaut, sauf demande explicite contraire.

4. **Assets**
   - usage des PNG réels pour le réacteur ;
   - usage des PNG réels pour les modules laser.

5. **Workflow dépôt**
   - mise à jour de `fusion.version` ;
   - synchronisation de `fusion.manifest.json` ;
   - vérification/adaptation de `install.lua`.

---

## Règle nouvelle obligatoire

### Interdiction de tronquer automatiquement les textes dans l’interface Tom

À partir de maintenant :

- aucun texte important ne doit être coupé automatiquement dans l’interface Tom ;
- la troncature automatique ne doit plus être utilisée comme solution normale de rendu.

Si un contenu est trop long, les solutions autorisées sont :

- redimensionnement de zone ;
- reflow ;
- multi-ligne ;
- libellé court conçu pour la page ;
- scroll/log dédié si nécessaire ;
- redistribution de l’espace.

Mais **pas** de coupe brutale systématique.

---

## Axes de travail

### 1. Finaliser la modularisation par pages de l’interface Tom

Chaque page Tom disponible doit être une vraie unité modulaire.

#### Exigences
- chaque page doit avoir son propre fichier ;
- chaque page doit avoir son propre rendu ;
- chaque page doit avoir sa logique de composition propre ;
- chaque page doit avoir ses interactions spécifiques si nécessaire ;
- l’orchestrateur Tom principal ne doit plus contenir tout le rendu inline.

#### Cible
Le fichier principal Tom doit devenir un **orchestrateur léger** :
- état partagé ;
- page active ;
- navigation ;
- dispatch vers les pages ;
- accès runtime partagé ;
- rendu de structure commune seulement.

---

### 2. Clarifier la séparation entre logique partagée et logique spécifique

#### À centraliser
- thème / design tokens ;
- helpers de layout partagé ;
- composants UI partagés ;
- navigation ;
- helpers texte ;
- helpers hit-testing ;
- helpers assets ;
- formateurs runtime ;
- règles communes de panel/header/footer.

#### À laisser dans chaque page
- contenu spécifique ;
- disposition spécifique ;
- labels spécifiques ;
- logique visuelle spécifique ;
- zones propres à la page.

Objectif :
- ne pas laisser du code spécifique de page dispersé dans les fichiers communs ;
- ne pas mettre toute la logique dans un seul fichier central.

---

### 3. Revoir tout le code Tom dans une logique 100 % native-pixel

L’interface Tom doit être pensée comme une interface **native-pixel**.

Cela implique une réanalyse de tout ce qui concerne :

- layout ;
- texte ;
- tailles ;
- padding ;
- hitboxes ;
- placement d’assets ;
- header/footer ;
- navigation ;
- panel bounds ;
- zones tactiles.

#### Ce qui doit disparaître
- les hypothèses héritées d’une logique terminal/monitor/grid ;
- les unités textuelles utilisées comme si elles étaient suffisantes pour le rendu Tom ;
- les restes de logique monitor si elles nuisent au rendu natif.

#### Ce qui doit exister
- métriques explicites en pixels ;
- dimensions minimales explicites ;
- calculs de bounds cohérents ;
- logique de texte adaptée au pixel natif ;
- hitboxes cohérentes avec un usage tactile terrain.

---

### 4. Centraliser proprement la navigation Tom

La navigation Tom doit être une brique dédiée.

#### La navigation doit gérer
- la liste des pages disponibles ;
- l’ordre des pages ;
- la page active ;
- les labels d’onglets ;
- les hitboxes tactiles ;
- l’affichage de la barre de navigation ;
- l’état actif/inactif.

#### Objectif
- éviter d’avoir la navigation recodée ou partiellement répartie dans plusieurs pages ;
- rendre la navigation proprement réutilisable et testable ;
- faciliter l’ajout de pages futures.

---

### 5. Centraliser proprement les assets Tom

Les assets Tom doivent être gérés proprement, en particulier :

- image PNG du réacteur ;
- image PNG du module laser ;
- logique d’empilement des modules laser ;
- mise à l’échelle ;
- centrage ;
- positionnement ;
- lecture du nombre de modules à partir de la source de configuration/installateur/runtime.

#### Objectif
- éviter de disperser le chargement et le placement des assets dans plusieurs pages ;
- rendre leur gestion cohérente et maintenable ;
- garantir que les modules laser affichés correspondent bien au paramètre réel.

---

### 6. Revoir la structure de l’orchestrateur principal

Le système global doit rester cohérent côté bootstrap/runtime.

Il faut réévaluer :

- l’orchestration principale ;
- la séparation entre runtime, UI, IO et dispatch ;
- la responsabilité réelle de l’orchestrateur principal.

#### Objectif
- éviter un fichier principal qui sait tout faire ;
- clarifier les responsabilités ;
- faciliter l’évolution future des backends d’affichage.

---

### 7. Faire une vraie passe de nettoyage du code mort

Une fois la séparation stabilisée, il faut faire une analyse sérieuse du code mort.

#### À rechercher
- branches de rendu devenues inutiles ;
- vieux chemins Tom obsolètes ;
- helpers dupliqués ;
- wrappers non utilisés ;
- modules zombies ;
- imports inutilisés ;
- compatibilité legacy inutile ;
- code de debug dépassé ;
- anciennes étapes de refactor laissées en place.

#### Politique
- supprimer si confirmé mort ;
- documenter si doute ;
- ne pas supprimer à l’aveugle.

---

### 8. Commenter ce qui doit l’être

Le projet a besoin de commentaires utiles, pas décoratifs.

#### À commenter en priorité
- rôles des modules ;
- orchestration de l’UI Tom ;
- séparation classique / Tom ;
- règles native-pixel ;
- navigation ;
- chargement des assets ;
- logique d’empilement des modules laser ;
- règles de sécurité runtime ;
- couplage version / manifeste / installateur ;
- logique “pas de troncature”.

#### Interdiction
- ne pas commenter des évidences triviales ;
- ne pas polluer le code de commentaires inutiles.

---

### 9. Rendre l’adaptativité homogène sur toutes les pages

Toutes les pages Tom doivent fonctionner dans le même système adaptatif.

Chaque page doit recevoir un contexte cohérent contenant au minimum :
- largeur/hauteur runtime ;
- densité active ;
- palette ;
- métriques de texte ;
- bounds partagés ;
- contexte tactile ;
- état runtime nécessaire ;
- infos de navigation.

#### Objectif
- éviter que chaque page réinvente sa propre logique de dimensionnement ;
- garantir une cohérence globale ;
- éviter qu’une page casse alors qu’une autre fonctionne.

---

### 10. Revoir les logs et le debug pour refléter la nouvelle architecture

Les logs doivent refléter la structure réelle du code.

#### À prévoir
- page active ;
- backend actif ;
- wrapper actif ;
- état navigation ;
- état assets ;
- nombre de modules laser ;
- densité active ;
- états de layout ;
- suppression des références à des chemins morts.

#### Objectif
- avoir un debug fiable ;
- ne pas conserver des logs qui décrivent une ancienne architecture.

---

### 11. Synchronisation obligatoire version / manifeste / installateur

À chaque itération structurelle :
- incrémenter `fusion.version` ;
- synchroniser `fusion.manifest.json` ;
- vérifier `install.lua` ;
- adapter `install.lua` si nouveaux fichiers/modules/assets.

Même si `install.lua` ne change pas, le débrief doit dire explicitement qu’il a été vérifié.

---

## Architecture cible recommandée

### Tom UI

Structure cible suggérée :

- `ui/toms/fusion_panel.lua` → orchestrateur léger
- `ui/toms/nav.lua` → navigation
- `ui/toms/theme.lua` → thème et métriques
- `ui/toms/layout.lua` → layout partagé
- `ui/toms/components.lua` → composants communs
- `ui/toms/assets.lua` → assets et placement
- `ui/toms/pages/supervision.lua`
- `ui/toms/pages/diagnostics.lua`
- `ui/toms/pages/update.lua`
- `ui/toms/pages/config.lua`
- `ui/toms/pages/setup.lua`
- `ui/toms/pages/manual.lua`
- autres pages si elles existent réellement

Cette structure peut être adaptée aux conventions exactes du dépôt, mais l’esprit doit rester :
- orchestrateur léger ;
- briques partagées centralisées ;
- pages séparées.

---

## Ordre d’exécution recommandé

### Phase 1 — Réanalyse complète de l’état actuel
- relire tout le dépôt concerné ;
- identifier ce qui a déjà été séparé ;
- identifier ce qui reste centralisé ;
- identifier les doublons et zones techniques fragiles.

### Phase 2 — Stabilisation de l’architecture par pages
- finaliser la séparation de chaque page Tom ;
- alléger l’orchestrateur principal ;
- fixer les responsabilités de chaque module.

### Phase 3 — Centralisation des briques partagées
- navigation ;
- assets ;
- texte ;
- hit-testing ;
- formatage ;
- métriques partagées.

### Phase 4 — Révision native-pixel
- supprimer les restes de logique monitor/grid nuisibles ;
- revoir tout le système texte/layout/hitboxes ;
- appliquer la règle “pas de troncature”.

### Phase 5 — Nettoyage du code mort
- supprimer les branches obsolètes ;
- nettoyer les imports ;
- retirer les doubles chemins devenus inutiles.

### Phase 6 — Commentaires utiles
- documenter l’architecture et les règles importantes.

### Phase 7 — Logs/debug
- réaligner le debug sur la nouvelle structure.

### Phase 8 — Synchronisation dépôt
- version ;
- manifeste ;
- installateur ;
- commit ;
- push.

---

## Critères d’acceptation

La modularisation et la centralisation sont considérées réussies seulement si :

1. chaque page Tom a son propre fichier ;
2. l’orchestrateur Tom est allégé ;
3. la navigation est centralisée proprement ;
4. les assets sont gérés proprement ;
5. la logique partagée est centralisée ;
6. la logique spécifique est bien répartie par page ;
7. l’UI Tom est cohérente avec une logique native-pixel ;
8. aucune troncature automatique de texte n’est encore utilisée dans l’UI Tom ;
9. le code mort confirmé a été traité ;
10. les commentaires utiles ont été ajoutés ;
11. l’UI classique reste disponible ;
12. l’UI Tom reste disponible ;
13. la sélection terrain reste valide ;
14. le backend Tom natif reste intact ;
15. `fusion.version` est mis à jour ;
16. `fusion.manifest.json` est synchronisé ;
17. `install.lua` est vérifié et adapté si nécessaire.

---

## Livrables attendus

1. liste exacte des fichiers modifiés ;
2. liste exacte des fichiers créés ;
3. liste exacte des fichiers supprimés ;
4. résumé en français ;
5. liste complète des pages Tom identifiées ;
6. mapping page → fichier ;
7. liste de la logique partagée centralisée ;
8. liste de la logique spécifique laissée par page ;
9. explication des changements faits pour la logique native-pixel ;
10. explication de la suppression de la troncature ;
11. liste du code mort retiré ;
12. liste des commentaires utiles ajoutés ;
13. explication des changements dans les logs/debug ;
14. mise à jour de `fusion.version` ;
15. mise à jour de `fusion.manifest.json` ;
16. vérification ou modification de `install.lua` ;
17. état du commit ;
18. état du push ;
19. tests manuels recommandés.
