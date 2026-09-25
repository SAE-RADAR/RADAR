# RADAR

## Choix de la salle de départ

Au lancement, le joueur arrive dans une salle d'accueil (`scenes/navigation/room_choice/welcome_room.tscn`) face à un écran. Il vise la salle voulue avec le rayon laser de sa manette ou de sa main, puis appuie sur la gâchette ou pince les doigts pour valider. Ce n'est pas une des interactions, c'est une aide à la navigation pour les tests et les démos.

- **ON/OFF** : `Interactions.room_choice` dans `autoload/interactions.gd`. Sur OFF, l'application démarre directement dans `Rooms.DEFAULT_ROOM` (les thermes).
- **Changer de salle depuis le code** : `Rooms.go_to("thermes")` ou `Rooms.go_to("gros_pilier")`. Le changement de scène se fait avec un fondu au noir.
- **Ajouter une salle** : l'ajouter dans `Rooms.SCENES` (`rooms.gd`) et dans `ROOMS` (`room_menu.gd`), avec le nom du bouton et l'image de preview (dans `previews/`, en 640×360).
- **Point d'apparition** : c'est le `XROrigin3D` de chaque scène de salle (position et orientation), placé par `player_spawn.gd`.
- **Tests** : la propriété `skip_to` de la salle d'accueil permet de sauter le choix. Sur PC, les touches 1 et 2 envoient dans chaque salle.
- L'écran est un `XRToolsViewport2DIn3D` qui affiche la scène 2D `room_menu.tscn`. Chaque main porte un `XRToolsFunctionPointer`.
