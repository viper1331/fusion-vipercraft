# PLANS.md

## ExecPlan — Modularisation complète, centralisation et amélioration du code

### Statut

Plan actif.

---

## Règle d’exécution

Ce plan doit être exécuté **phase par phase**.

### Instruction impérative
- À chaque itération, exécuter **uniquement la phase demandée**.
- Ne pas anticiper les phases suivantes.
- Ne pas re-définir le plan dans le prompt si `PLANS.md` est déjà présent dans le dépôt.
- Utiliser `AGENTS.md` et ce fichier comme **source de vérité**.
- Chaque phase doit être traitée comme une unité de travail autonome.
- Si une phase produit des modifications utiles, cohérentes et exploitables, cette phase doit être finalisée complètement dans la même itération :
  - vérification des fichiers impactés,
  - mise à jour de `fusion.version` si nécessaire,
  - synchronisation de `fusion.manifest.json` si nécessaire,
  - vérification/adaptation de `install.lua` si nécessaire,
  - commit,
  - push.
- Si une phase est purement analytique et ne modifie aucun fichier, ne pas forcer un faux commit. Dans ce cas, indiquer explicitement qu’aucun changement de code n’a été nécessaire.

---

## Objectif global

Faire évoluer le projet vers une architecture :

- plus modulaire ;
- plus claire ;
- plus maintenable ;
- plus cohérente entre UI classique et UI Tom ;
- plus robuste sur le terrain ;
- plus propre sur la gestion des pages, des composants, des assets, de la navigation et du runtime.

Le but n’est **pas** de réécrire gratuitement ce qui fonctionne déjà.  
Le but est de **consolider l’existant validé**, d’éliminer les zones techniques fragiles et de structurer proprement la suite du projet.

---

## Invariants à préserver

Les éléments suivants sont considérés comme **validés** et ne doivent pas être cassés :

### 1. Backend Tom natif
- pipeline Tom natif validé ;
- rendu natif GPU ;
- dimensions runtime natives ;
- compatibilité avec le debug Tom natif.

### 2. Coexistence des interfaces
- interface classique disponible ;
- interface Tom disponible ;
- sélection automatique du backend selon la détection terrain.

### 3. Comportements runtime
- adaptativité runtime ;
- reflow à la volée ;
- logique de navigation ;
- logique de sécurité existante ;
- `allow_control = false` par défaut, sauf demande explicite contraire.

### 4. Assets
- usage des PNG réels pour le réacteur ;
- usage des PNG réels pour les modules laser.

### 5. Workflow dépôt
- mise à jour de `fusion.version` ;
- synchronisation de `fusion.manifest.json` ;
- vérification/adaptation de `install.lua`.

---

## Règle Git / Version / Distribution par phase

Chaque phase doit être clôturée proprement si elle produit des changements utiles.

### Si la phase modifie le code, les assets, la structure ou la distribution
Alors, dans la même phase, il faut :
1. vérifier les fichiers modifiés ;
2. incrémenter `fusion.version` si nécessaire ;
3. synchroniser `fusion.manifest.json` si nécessaire ;
4. vérifier `install.lua` ;
5. modifier `install.lua` si la phase impacte les fichiers distribués, installés, chargés ou configurés ;
6. faire un commit clair ;
7. pousser les changements sur le dépôt distant.

### Si la phase est purement analytique
- ne pas forcer un commit vide ou artificiel ;
- indiquer explicitement dans le débrief :
  - qu’aucun fichier n’a été modifié,
  - qu’aucun commit n’a été nécessaire,
  - qu’aucun push n’a été nécessaire.

### Principe
Le commit et le push ne doivent pas être reportés à la fin de tout le plan.  
Ils doivent être faits **à la fin de chaque phase**, dès lors que cette phase produit un état cohérent du dépôt.

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

## Architecture cible recommandée

### Structure Tom UI cible

La structure cible suggérée est :

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
- pages séparées ;
- rendu Tom pensé **100 % native-pixel**.

---

## Axes de travail

### A. Finaliser la modularisation par pages de l’interface Tom
Chaque page Tom disponible doit être une vraie unité modulaire.

#### Exigences
- chaque page doit avoir son propre fichier ;
- chaque page doit avoir son propre rendu ;
- chaque page doit avoir sa logique de composition propre ;
- chaque page doit avoir ses interactions spécifiques si nécessaire ;
- l’orchestrateur Tom principal ne doit plus contenir tout le rendu inline.

### B. Clarifier la séparation entre logique partagée et logique spécifique

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

### C. Revoir tout le code Tom dans une logique 100 % native-pixel
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

### D. Centraliser proprement la navigation Tom
La navigation Tom doit être une brique dédiée.

### E. Centraliser proprement les assets Tom
Les assets Tom doivent être gérés proprement, en particulier :
- image PNG du réacteur ;
- image PNG du module laser ;
- logique d’empilement des modules laser ;
- mise à l’échelle ;
- centrage ;
- positionnement ;
- lecture du nombre de modules depuis la configuration/installateur/runtime.

### F. Revoir la structure de l’orchestrateur principal
Le système global doit rester cohérent côté bootstrap/runtime.

### G. Faire une vraie passe de nettoyage du code mort
Après la séparation stabilisée :
- suppression des branches obsolètes ;
- nettoyage des imports ;
- retrait des doubles chemins devenus inutiles.

### H. Commenter ce qui doit l’être
Commentaires utiles sur :
- rôles des modules ;
- séparation classique / Tom ;
- règles native-pixel ;
- navigation ;
- chargement des assets ;
- logique d’empilement des modules laser ;
- règles de sécurité runtime ;
- couplage version / manifeste / installateur ;
- logique “pas de troncature”.

### I. Rendre l’adaptativité homogène sur toutes les pages
Toutes les pages Tom doivent fonctionner dans le même système adaptatif.

### J. Revoir les logs et le debug pour refléter la nouvelle architecture
Les logs doivent refléter la structure réelle du code.

### K. Synchronisation obligatoire version / manifeste / installateur
À chaque itération structurelle :
- incrémenter `fusion.version` ;
- synchroniser `fusion.manifest.json` ;
- vérifier `install.lua` ;
- adapter `install.lua` si nouveaux fichiers/modules/assets.

---

## Ordre d’exécution recommandé

L’ordre recommandé est le suivant :

1. figer les invariants backend/runtime ;
2. réanalyser l’état actuel du dépôt ;
3. finaliser la séparation par pages ;
4. extraire navigation et assets ;
5. centraliser les helpers partagés ;
6. imposer la règle “aucune troncature” et revoir le moteur de texte ;
7. nettoyer les doublons et le code mort ;
8. réaligner logs, manifeste, installateur et version.

---

# PHASES

---

## Phase 1 — Réanalyse complète de l’état actuel du dépôt

### Objectif
Établir un diagnostic propre sur :
- ce qui est déjà séparé ;
- ce qui reste trop centralisé ;
- ce qui est dupliqué ;
- ce qui est mort ou suspect ;
- ce qui devra être traité dans les phases suivantes.

### Portée minimale
Analyser au minimum :
- `core/`
- `io/`
- `ui/`
- `tests/`
- `fusion.lua`
- `diagviewer.lua`
- `install.lua`
- `fusion.manifest.json`
- `fusion.version`
- assets/config/logs liés
- navigation/page-state handling
- fichiers Tom déjà séparés

### Diagnostic attendu
Identifier :
1. toutes les pages Tom actuellement présentes ;
2. la correspondance page → fichier ;
3. ce qui est encore trop centralisé ;
4. ce qui est déjà correctement partagé ;
5. ce qui est encore mal placé ;
6. les incohérences native-pixel restantes ;
7. les usages restants de troncature ;
8. les suspicions de code mort ;
9. les points faibles manifeste/installateur/version.

### Résultat attendu
- rapport d’architecture détaillé en français ;
- liste exacte des fichiers inspectés ;
- liste exacte des fichiers à traiter en Phase 2 ;
- indication explicite des zones prioritaires.

### Règle
- Cette phase est **diagnostic-first**.
- Ne pas engager une refonte lourde pendant cette phase.
- Si aucun fichier n’est modifié, ne pas forcer commit/push.
- Si la phase produit malgré tout une petite correction utile et cohérente, alors appliquer la règle Git/version/distribution par phase.

---

## Phase 2 — Finalisation de l’architecture par pages Tom

### Objectif
Faire de chaque page Tom une vraie unité modulaire.

### Travaux attendus
- finaliser un fichier par page ;
- sortir le rendu spécifique de l’orchestrateur ;
- alléger `ui/toms/fusion_panel.lua` ;
- clarifier quelles responsabilités restent dans l’orchestrateur.

### Résultat attendu
- chaque page a son fichier ;
- l’orchestrateur Tom est visiblement plus léger ;
- la navigation et le dispatch fonctionnent toujours.

### Clôture de phase
Si cette phase produit des changements utiles :
- mettre à jour `fusion.version` si nécessaire ;
- synchroniser `fusion.manifest.json` si nécessaire ;
- vérifier/adapter `install.lua` si nécessaire ;
- faire un commit clair ;
- pousser les changements.

Si cette phase n’a produit aucun changement de code, l’indiquer explicitement dans le débrief.

---

## Phase 3 — Centralisation des briques partagées

### Objectif
Centraliser proprement ce qui est vraiment partagé.

### Travaux attendus
- navigation ;
- assets ;
- helpers texte ;
- helpers hit-testing ;
- formatage runtime ;
- composants réellement partagés ;
- métriques globales.

### Résultat attendu
- moins de duplication ;
- moins de logique partagée dispersée ;
- moins de logique page-specific dans les fichiers communs.

### Clôture de phase
Si cette phase produit des changements utiles :
- mettre à jour `fusion.version` si nécessaire ;
- synchroniser `fusion.manifest.json` si nécessaire ;
- vérifier/adapter `install.lua` si nécessaire ;
- faire un commit clair ;
- pousser les changements.

Si cette phase n’a produit aucun changement de code, l’indiquer explicitement dans le débrief.

---

## Phase 4 — Révision native-pixel et suppression de la troncature

### Objectif
Faire de l’UI Tom une interface pleinement cohérente avec un rendu natif pixel.

### Travaux attendus
- retirer les hypothèses monitor/grid nuisibles ;
- revoir le système texte ;
- désactiver/remplacer la troncature automatique ;
- mettre en place :
  - reflow ;
  - multi-ligne ;
  - réallocation d’espace ;
  - labels compacts conçus par page ;
  - zones scrollables si nécessaire.

### Résultat attendu
- aucun texte important tronqué ;
- layout Tom cohérent avec le pixel natif ;
- hitboxes et panels alignés sur cette logique.

### Clôture de phase
Si cette phase produit des changements utiles :
- mettre à jour `fusion.version` si nécessaire ;
- synchroniser `fusion.manifest.json` si nécessaire ;
- vérifier/adapter `install.lua` si nécessaire ;
- faire un commit clair ;
- pousser les changements.

Si cette phase n’a produit aucun changement de code, l’indiquer explicitement dans le débrief.

---

## Phase 5 — Navigation Tom dédiée et propre

### Objectif
Transformer la navigation Tom en module robuste et réutilisable.

### Travaux attendus
- module `nav.lua` ou équivalent ;
- table des pages ;
- état actif ;
- hitboxes tactiles ;
- rendu de la barre de navigation ;
- compatibilité avec reflow et runtime adaptatif.

### Résultat attendu
- navigation centralisée ;
- plus de logique de nav éparpillée ;
- navigation maintenable.

### Clôture de phase
Si cette phase produit des changements utiles :
- mettre à jour `fusion.version` si nécessaire ;
- synchroniser `fusion.manifest.json` si nécessaire ;
- vérifier/adapter `install.lua` si nécessaire ;
- faire un commit clair ;
- pousser les changements.

Si cette phase n’a produit aucun changement de code, l’indiquer explicitement dans le débrief.

---

## Phase 6 — Assets Tom et pile de modules laser

### Objectif
Centraliser le traitement des assets et de leur placement.

### Travaux attendus
- chargement du PNG réacteur ;
- chargement du PNG module laser ;
- gestion du scale/centrage ;
- empilement vertical des modules laser ;
- lecture du nombre de modules depuis la source de vérité configurée ;
- cohérence avec manifeste/installateur.

### Résultat attendu
- assets gérés proprement ;
- logique de modules laser maintenable ;
- plus d’asset logic dispersée dans plusieurs pages.

### Clôture de phase
Si cette phase produit des changements utiles :
- mettre à jour `fusion.version` si nécessaire ;
- synchroniser `fusion.manifest.json` si nécessaire ;
- vérifier/adapter `install.lua` si nécessaire ;
- faire un commit clair ;
- pousser les changements.

Si cette phase n’a produit aucun changement de code, l’indiquer explicitement dans le débrief.

---

## Phase 7 — Nettoyage du code mort, doublons et branches obsolètes

### Objectif
Faire une vraie passe de ménage, mais seulement une fois l’architecture stabilisée.

### Travaux attendus
- suppression des vieux chemins de rendu Tom obsolètes ;
- suppression des blocs page-specific restés dans l’orchestrateur ;
- suppression des doublons de helpers ;
- suppression des imports inutilisés ;
- nettoyage des sections de debug obsolètes ;
- retrait des branches legacy clairement mortes.

### Règle
- supprimer si confirmé mort ;
- documenter si doute ;
- ne pas supprimer à l’aveugle.

### Clôture de phase
Si cette phase produit des changements utiles :
- mettre à jour `fusion.version` si nécessaire ;
- synchroniser `fusion.manifest.json` si nécessaire ;
- vérifier/adapter `install.lua` si nécessaire ;
- faire un commit clair ;
- pousser les changements.

Si cette phase n’a produit aucun changement de code, l’indiquer explicitement dans le débrief.

---

## Phase 8 — Commentaires utiles et documentation interne

### Objectif
Documenter l’architecture utilement.

### Travaux attendus
Commentaires sur :
- rôles des modules ;
- séparation classique / Tom ;
- règles native-pixel ;
- logique “pas de troncature” ;
- navigation ;
- assets ;
- sécurité runtime ;
- couplage version/manifeste/installateur.

### Résultat attendu
- code plus lisible pour l’avenir ;
- meilleure maintenabilité.

### Clôture de phase
Si cette phase produit des changements utiles :
- mettre à jour `fusion.version` si nécessaire ;
- synchroniser `fusion.manifest.json` si nécessaire ;
- vérifier/adapter `install.lua` si nécessaire ;
- faire un commit clair ;
- pousser les changements.

Si cette phase n’a produit aucun changement de code, l’indiquer explicitement dans le débrief.

---

## Phase 9 — Révision des logs et du debug

### Objectif
Faire refléter la nouvelle architecture par les logs et le debug.

### Travaux attendus
- page active ;
- backend actif ;
- wrapper actif ;
- état navigation ;
- état assets ;
- module laser count ;
- densité active ;
- suppression des références aux vieux chemins morts.

### Résultat attendu
- debug fiable ;
- logs cohérents avec l’architecture réelle.

### Clôture de phase
Si cette phase produit des changements utiles :
- mettre à jour `fusion.version` si nécessaire ;
- synchroniser `fusion.manifest.json` si nécessaire ;
- vérifier/adapter `install.lua` si nécessaire ;
- faire un commit clair ;
- pousser les changements.

Si cette phase n’a produit aucun changement de code, l’indiquer explicitement dans le débrief.

---

## Phase 10 — Synchronisation finale du dépôt et validation

### Objectif
Aligner la distribution sur la nouvelle architecture.

### Travaux attendus
- mise à jour de `fusion.version` ;
- mise à jour de `fusion.manifest.json` ;
- vérification/adaptation de `install.lua` ;
- commit propre ;
- push.

### Résultat attendu
- repo cohérent ;
- distribution cohérente ;
- itération clôturable proprement.

### Clôture de phase
Si cette phase produit des changements utiles :
- mettre à jour `fusion.version` si nécessaire ;
- synchroniser `fusion.manifest.json` si nécessaire ;
- vérifier/adapter `install.lua` si nécessaire ;
- faire un commit clair ;
- pousser les changements.

Si cette phase n’a produit aucun changement de code, l’indiquer explicitement dans le débrief.

---

## Critères d’acceptation globaux

Le plan est considéré réussi seulement si :

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

## Livrables attendus à chaque phase

À chaque phase exécutée, le retour doit contenir :

1. liste exacte des fichiers inspectés ;
2. liste exacte des fichiers modifiés ;
3. liste exacte des fichiers créés ;
4. liste exacte des fichiers supprimés ;
5. résumé en français ;
6. ce qui a été réellement fait dans la phase ;
7. ce qui reste pour la phase suivante ;
8. état de `fusion.version` ;
9. état de `fusion.manifest.json` ;
10. état de `install.lua` ;
11. état du commit ;
12. état du push ;
13. tests manuels recommandés.

### Règle de sortie
- si aucun fichier n’a été modifié, le retour doit le dire explicitement ;
- si des fichiers ont été modifiés, la phase doit normalement être clôturée avec commit + push ;
- il ne faut pas attendre la fin de tout le plan pour publier une phase terminée.
