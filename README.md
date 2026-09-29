# RADAR

## Choix de la salle de départ

Au lancement, le joueur arrive dans une salle d'accueil (`scenes/navigation/room_choice/welcome_room.tscn`) face à un écran. Il vise la salle voulue avec le rayon laser de sa manette ou de sa main, puis appuie sur la gâchette ou pince les doigts pour valider. Ce n'est pas une des interactions, c'est une aide à la navigation pour les tests et les démos.

- **ON/OFF** : `Interactions.room_choice` dans `autoload/interactions.gd`. Sur OFF, l'application démarre directement dans `Rooms.DEFAULT_ROOM` (les thermes).
- **Changer de salle depuis le code** : `Rooms.go_to("thermes")` ou `Rooms.go_to("gros_pilier")`. Le changement de scène se fait avec un fondu au noir.
- **Ajouter une salle** : l'ajouter dans `Rooms.SCENES` (`rooms.gd`) et dans `ROOMS` (`room_menu.gd`), avec le nom du bouton et l'image de preview (dans `previews/`, en 640×360).
- **Point d'apparition** : c'est le `XROrigin3D` de chaque scène de salle (position et orientation), placé par `player_spawn.gd`.
- **Tests** : la propriété `skip_to` de la salle d'accueil permet de sauter le choix. Sur PC, les touches 1 et 2 envoient dans chaque salle.
- L'écran est un `XRToolsViewport2DIn3D` qui affiche la scène 2D `room_menu.tscn`. Chaque main porte un `XRToolsFunctionPointer`.


## Nuages de vapeur

De la vapeur s'élève au-dessus de l'eau des bassins. Quand on passe la main dedans, elle est repoussée.

- **ON/OFF** : `Interactions.steam` dans `autoload/interactions.gd`.
- **Ajouter de la vapeur sur un bassin** : instancier `scenes/effects/steam/steam_clouds.tscn` comme enfant d'un `WaterVolume`. L'effet prend automatiquement la taille de l'eau. Renseigner `left_hand` et `right_hand` avec les `XRController3D` pour que les mains repoussent la vapeur.
- **Réglages** :
  - dans le script : `clouds_per_square_meter` (quantité), `hand_radius` et `hand_push` (effet des mains) ;
  - dans le matériau `steam.gdshader` : `density` (opacité), `color`, `wisp_scale` et `wisp_speed` (volutes), `near_fade_start` et `near_fade_end` (fondu près de la tête) ;
  - dans le `ParticleProcessMaterial` : vitesse de montée, durée de vie, taille.
- Les mains repoussent la vapeur grâce à un `GPUParticlesAttractorSphere3D` de force négative, ajouté sur chaque manette au lancement.


## Contrôle avec les mains

L'application se contrôle sans manettes, avec le suivi des mains du Quest.

- **Se téléporter** : pincer le pouce et l'index de la main droite et garder le pincement, viser avec la main, puis relâcher. Fermer le poing pendant qu'on vise annule la téléportation.
- **Choisir une salle** : viser le bouton avec le rayon de la main, puis pincer.
- Le geste est détecté par l'autoload `HandGestures` (`scenes/navigation/hand_gestures/hand_gestures.gd`). Il crée une action virtuelle `gesture_select` sur chaque main :
  - avec une manette, elle recopie la gâchette ;
  - avec la main, elle n'est pressée que pour un vrai pincement : index loin de la paume (pas un poing), main vue ouverte avant, pincement tenu 0,15 s.
- Les fonctions XR Tools qui doivent réagir au geste utilisent `gesture_select` comme action : `teleport_button_action` pour la téléportation, `active_button_action` pour le pointeur.
- Réglages dans `hand_gestures.gd` : `pinch_start` et `pinch_end` (distance pouce-index), `min_index_to_palm`, `hold_time`, `open_time`. Avec `debug = true`, les distances mesurées s'affichent dans le journal du casque (`adb logcat`).
- Nécessite `xr/openxr/extensions/hand_tracking` et `hand_interaction_profile` activés dans les paramètres du projet.
