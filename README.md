# RADAR

## Choix de la salle de départ

Au lancement, le joueur arrive dans une salle d'accueil (`scenes/navigation/room_choice/welcome_room.tscn`) face à un écran. Il vise la salle voulue avec le rayon laser de sa manette ou de sa main, puis appuie sur la gâchette ou pince les doigts pour valider. Ce n'est pas une des interactions, c'est une aide à la navigation pour les tests et les démos.

- **ON/OFF** : `Interactions.room_choice` dans `autoload/interactions.gd`. Sur OFF, l'application démarre directement dans `Rooms.DEFAULT_ROOM` (les thermes).
- **Changer de salle depuis le code** : `Rooms.go_to("thermes")` ou `Rooms.go_to("gros_pilier")`. Le changement de scène se fait avec un fondu au noir.
- **Ajouter une salle** : l'ajouter dans `Rooms.SCENES` (`rooms.gd`) et dans `ROOMS` (`room_menu.gd`), avec le nom du bouton et l'image de preview (dans `previews/`, en 640×360).
- **Point d'apparition** : c'est le `XROrigin3D` de chaque scène de salle (position et orientation), placé par `player_spawn.gd`.
- **Tests** : la propriété `skip_to` de la salle d'accueil permet de sauter le choix. Sur PC, les touches 1 et 2 envoient dans chaque salle.
- L'écran est un `XRToolsViewport2DIn3D` qui affiche la scène 2D `room_menu.tscn`. Chaque main porte un `XRToolsFunctionPointer`.

## Tuyaux

Les tuyaux (`Pipe`, `scenes/effects/pipe.gd`) montrent comment l'eau circule dans les thermes. Ils sont cachés dans les murs et n'apparaissent que dans les trous creusés avec la main (`HandDissolve`). L'eau y prend la couleur de sa température (bleu froid → rouge chaud) et des flèches de la même couleur avancent avec le flux.

- **Ajouter un tuyau** : ajouter un nœud `Pipe` (c'est un `Path3D`) et dessiner son trajet avec la courbe, juste derrière la surface du scan. L'eau va du premier point au dernier ; les angles vifs deviennent des coudes (`bend_radius`).
- **Réglages par tuyau** : `inlet_temperature` / `outlet_temperature` (°C, en entrée et en sortie), `flow_speed` (m/s, 0 = eau immobile, sans flèches ; modifiable en jeu comme une vanne), `radius`.
- **Échelle des couleurs** : commune à tous les tuyaux, dans `pipe_water_material.tres` (`temperature_ramp` et `temperature_range`, 10 à 45 °C par défaut). Taille et espacement des flèches au même endroit.
- **Visibilité** : `HandDissolve` publie ses trous dans les globales de shader `DISSOLVE_SOURCE_0/1` (`project.godot`). Les tuyaux sont toujours visibles dans l'éditeur ; `always_visible` les montre aussi en jeu, pour déboguer (les murs les cachent quand même).
- **Démo** : `scenes/effects/pipe_demo.tscn`, sur PC. Maintenir le clic droit sur un mur pour creuser.
