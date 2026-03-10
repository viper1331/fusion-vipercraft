# Analyse du script `fusion_cc.lua`

## Vue d'ensemble
Le dépôt contient un seul programme CC:Tweaked (`-- fusion_cc.lua`) qui pilote un réacteur de fusion Mekanism via périphériques et relais redstone.

## Architecture
- **Configuration (`CFG`)**: noms de périphériques préférés, seuils d'énergie/charge laser, mapping des actions redstone.
- **État runtime (`state`)**: états automation, capteurs (réacteur, laser, énergie, gaz), UI, alarmes.
- **Inventaire matériel (`hw`)**: wrappers de périphériques détectés dynamiquement + rôles des block readers.
- **Boucle principale**: `refreshAll()` -> `fullAuto()` -> `drawUI()` -> gestion événements clavier/tactile.

## Logique d'automatisation
- Charge laser automatique entre `laserChargeStartPct` et `laserChargeStopPct`.
- Séquence d'allumage automatique quand:
  - réacteur formé,
  - pas déjà allumé,
  - énergie laser au-dessus du seuil (`ignitionLaserEnergyThreshold`).
- Contrôle du D-T fuel selon niveau d'énergie induction (`energyLowPct` / `energyHighPct`).
- Garde-fou sécurité: arrêt d'urgence si réacteur absent (optionnel via config).

## Points forts
- Détection robuste des périphériques par nom **et** par présence de méthodes.
- Appels périphériques encapsulés (`safeCall`, `tryMethods`) réduisant les crashs.
- UI tactile + fallback clavier, avec sélection dynamique de moniteur.
- Gestion cohérente des modes auto (`autoMaster`, `fusionAuto`, `chargeAuto`, `gasAuto`).

## Risques / limites
1. **Fichier au nom atypique** (`-- fusion_cc.lua`): fragile pour scripts/outils shell.
2. **Scan matériel à chaque tick** (`refreshAll` rescane tout): potentiellement coûteux en grand setup.
3. **Alerte "DANGER" écrasable**: `hardStop` pose `alert = "DANGER"`, mais `updateAlerts()` ne conserve pas explicitement cet état et peut le remplacer.
4. **Logique monitorList paginée non exploitée**: variable `monitorPage` définie mais pas utilisée.
5. **Énergie inconnue**: en absence de lecture induction, certaines décisions passent en mode dégradé sans signalement explicite fort.

## Recommandations prioritaires
1. Renommer le fichier script vers un nom sans préfixe `-`.
2. Ne rescanner les périphériques que sur événements `peripheral`/`peripheral_detach` (ou à cadence lente distincte).
3. Verrouiller l'état `DANGER` jusqu'à acquittement manuel.
4. Ajouter un mode "diagnostic" affichant la source réelle de chaque donnée (logic adapter vs reactor vs block reader).
5. Introduire un petit module de test simulé (mock périphériques) pour valider les transitions critiques (ignition, e-stop, bascule gaz).
