# RADAR

## Choix du mode et de la salle de départ

Au lancement, le joueur arrive dans une salle d'accueil (`scenes/navigation/room_choice/welcome_room.tscn`) face à un écran. Il choisit d'abord le mode, **réalité virtuelle** ou **réalité augmentée**, puis la salle. Il vise avec le rayon laser de sa manette ou de sa main, puis appuie sur la gâchette ou pince les doigts pour valider.

- **Mode** : gardé dans l'autoload `AppMode` (`autoload/app_mode.gd`), `AppMode.is_ar()`. En VR, tout fonctionne comme avant. En AR, voir plus bas.
- **Choix de la salle ON/OFF** : `Interactions.room_choice` dans `autoload/interactions.gd`. Sur OFF, le mode est quand même demandé, puis l'application va directement dans `Rooms.DEFAULT_ROOM` (les thermes). En AR, seules les salles de `Rooms.AR_ROOMS` sont proposées ; s'il n'y en a qu'une, on y va directement.
- **Changer de salle depuis le code** : `Rooms.go_to("thermes")` ou `Rooms.go_to("gros_pilier")`, après avoir réglé `AppMode.mode`. Le changement de scène se fait avec un fondu au noir.
- **Ajouter une salle** : l'ajouter dans `Rooms.SCENES` (`rooms.gd`) et dans `ROOMS` (`room_menu.gd`), avec le nom du bouton et l'image de preview (dans `previews/`, en 640×360). Pour l'AR, l'ajouter aussi dans `Rooms.AR_ROOMS` (voir plus bas).
- **Point d'apparition** : c'est le `XROrigin3D` de chaque scène de salle (position et orientation), placé par `player_spawn.gd` (en VR seulement).
- **Tests** : la propriété `skip_to` de la salle d'accueil permet de sauter le choix (`skip_to_ar` pour y aller en AR). Sur PC, les touches 1 et 2 envoient dans chaque salle en VR, la touche 3 dans les thermes en AR.
- L'écran est un `XRToolsViewport2DIn3D` qui affiche la scène 2D `room_menu.tscn`. Chaque main porte un `XRToolsFunctionPointer`.


## Réalité augmentée

En AR, le casque montre les vraies thermes en passthrough. Un QR code collé sur le site sert de repère : quand le casque le voit, le scan se cale sur les vrais murs. Le scan n'est alors plus dessiné, il sert de **masque** : les tuyaux, l'eau, la vapeur, etc. sont cachés derrière les vrais murs comme ils le seraient derrière le scan, et les trous creusés avec la main (`HandDissolve`) s'ouvrent dans ce masque.

- **Nœud** : `ARSession` (`scenes/world/ar/ar_session.gd`) dans la scène de la salle, juste après `XRToolsStartXR`. En VR il ne fait rien. En AR il active le passthrough, rend le fond transparent, désactive les déplacements (`vr_only` : téléportation, rotation, `PlayerBody` ; on marche pour de vrai) et cache le contenu (`content`) tant qu'aucun QR code n'a été vu.
- **Placer le QR code** : un nœud `QRMarker` (`scenes/world/ar/qr_marker.gd`) par code imprimé, posé sur le scan à l'endroit exact où le code est collé sur le vrai mur : centre du code, **+Y (vert) vers le haut du code, +Z (bleu) sortant de la face imprimée**. Dans l'éditeur, un carré de la taille du code (`size`) avec un onglet rouge sur le bord haut aide à le placer. Plus il correspond au vrai code, mieux le scan se cale.
  - ⚠️ Le `QRMarker` des thermes est pour l'instant à une position provisoire (0 ; 1,5 ; 0) : **il faut le déplacer sur le mur où le code est réellement collé.**
- **Contenu du QR code** : `data` du `QRMarker` (`RADAR:thermes` pour les thermes). Les QR codes avec un autre texte sont ignorés ; `data` vide accepte n'importe quel QR code. Plusieurs codes peuvent être placés dans une même salle : le plus proche de la tête est suivi.
- **Calage** : l'origine du joueur est déplacée pour que le code du scan tombe sur le vrai code. Elle reste droite (seul le cap est pris du code), ne suit que les codes à moins de `max_marker_distance` de la tête (3 m), et s'affine tant que le code est vu (`smoothing`).
- **Corriger l'alignement dans le casque** : **Y** (manette gauche) active la calibration : le scan s'affiche en transparence sur le passthrough. Stick gauche : déplacer ; stick droit : monter/descendre et tourner autour du premier `QRMarker` ; **B** (manette droite) : réinitialiser ; **Y** : valider. La correction est enregistrée par salle dans `user://ar_calibration.cfg` et affichée dans la console.
- **Masque** : trois passes sur le scan (`scan_mask.gdshader`, `scan_mask_clear.gdshader`, `scan_mask_overlay.gdshader`, partagées avec `scan_dissolve.gdshader` via `scan_dissolve.gdshaderinc`). La première écrit la profondeur du scan en noir, la deuxième remet ce noir en transparent pour laisser voir le passthrough, la troisième dessine le bord lumineux des trous (et le scan pendant la calibration).
- **Eau** : en AR, rien du vrai monde n'est dans l'image à réfracter. La globale de shader `PASSTHROUGH` fait dessiner l'eau comme une teinte (`passthrough_color`) d'autant plus opaque que l'eau est profonde (`passthrough_min_opacity` au minimum).
- **Effets additifs** : sur le passthrough, un mélange `blend_add` dessine aussi l'alpha et laisse voir le carré des particules. Utiliser `blend_premul_alpha` avec `ALPHA = 0.0` (comme `firefly.gdshader`), qui donne le même résultat en VR.
- **Ajouter l'AR à une salle** : y ajouter un `ARSession` (copier celui des thermes et ses chemins de nœuds) et au moins un `QRMarker`, puis ajouter la salle dans `Rooms.AR_ROOMS`.
- **Casque** : suivi des QR codes par l'extension OpenXR `XR_EXT_spatial_marker_tracking` (paramètres de projet `openxr/extensions/spatial_entity/enable_marker_tracking` et `enable_builtin_marker_tracking`). Sur Quest 3, d'après les retours de la communauté, il faut Horizon OS v83 ou plus récent. Imprimer le code avec sa marge blanche, le coller bien à plat, et éviter les reflets.


## Nuages de vapeur

De la vapeur s'élève au-dessus de l'eau des bassins. Quand on passe la main dedans, elle est repoussée.

- **ON/OFF** : `Interactions.steam` dans `autoload/interactions.gd`.
- **Ajouter de la vapeur sur un bassin** : instancier `scenes/effects/steam/steam_clouds.tscn` comme enfant d'un `WaterVolume`. L'effet prend automatiquement la taille de l'eau. Renseigner `left_hand` et `right_hand` avec les `XRController3D` pour que les mains repoussent la vapeur.
- **Réglages** :
  - dans le script : `clouds_per_square_meter` (quantité), `hand_radius` et `hand_push` (effet des mains) ;
  - dans le matériau `steam.gdshader` : `density` (opacité), `color`, `wisp_scale` et `wisp_speed` (volutes), `near_fade_start` et `near_fade_end` (fondu près de la tête) ;
  - dans le `ParticleProcessMaterial` : vitesse de montée, durée de vie, taille.
- Les mains repoussent la vapeur grâce à un `GPUParticlesAttractorSphere3D` de force négative, ajouté sur chaque manette au lancement.


## Tuyaux

Les tuyaux (`Pipe`, `scenes/effects/pipe.gd`) montrent comment l'eau circule dans les thermes. Ils sont cachés dans les murs et n'apparaissent que dans les trous creusés avec la main (`HandDissolve`). L'eau y prend la couleur de sa température (bleu froid → rouge chaud) et des flèches de la même couleur avancent avec le flux.

- **Ajouter un tuyau** : ajouter un nœud `Pipe` (c'est un `Path3D`) et dessiner son trajet avec la courbe, juste derrière la surface du scan. L'eau va du premier point au dernier ; les angles vifs deviennent des coudes (`bend_radius`).
- **Réglages par tuyau** : `inlet_temperature` / `outlet_temperature` (°C, en entrée et en sortie), `flow_speed` (m/s, 0 = eau immobile, sans flèches ; modifiable en jeu comme une vanne), `radius`.
- **Échelle des couleurs** : commune à tous les tuyaux, dans `pipe_water_material.tres` (quatre couleurs et `stop_temperatures`, de 10 °C en bleu à 45 °C en rouge par défaut). Taille et espacement des flèches au même endroit.
- **Visibilité** : `HandDissolve` publie ses trous dans les globales de shader `DISSOLVE_SOURCE_0/1` (`project.godot`). Les tuyaux sont toujours visibles dans l'éditeur ; `always_visible` les montre aussi en jeu, pour déboguer (les murs les cachent quand même).
- **Démo** : `scenes/effects/pipe_demo.tscn`, sur PC, avec 7 postes (touches 1 à 7) : tuyaux cachés dans les murs (maintenir le clic droit sur le mur pour creuser), échelle des températures, vitesses, refroidissement le long d'un tuyau, coudes et courbes, vanne changée en jeu (`pipe_demo_valve.gd`), et un petit circuit foyer → caldarium → tepidarium, aqueduc → frigidarium.
