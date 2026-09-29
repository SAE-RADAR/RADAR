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


## Tuyaux

Les tuyaux (`Pipe`, `scenes/effects/pipe.gd`) montrent comment l'eau circule dans les thermes. Ils sont cachés dans les murs et n'apparaissent que dans les trous creusés avec la main (`HandDissolve`). L'eau y prend la couleur de sa température (bleu froid → rouge chaud) et des flèches de la même couleur avancent avec le flux.

- **Ajouter un tuyau** : ajouter un nœud `Pipe` (c'est un `Path3D`) et dessiner son trajet avec la courbe, juste derrière la surface du scan. L'eau va du premier point au dernier ; les angles vifs deviennent des coudes (`bend_radius`).
- **Réglages par tuyau** : `inlet_temperature` / `outlet_temperature` (°C, en entrée et en sortie), `flow_speed` (m/s, 0 = eau immobile, sans flèches ; modifiable en jeu comme une vanne), `radius`.
- **Échelle des couleurs** : commune à tous les tuyaux, dans `pipe_water_material.tres` (quatre couleurs et `stop_temperatures`, de 10 °C en bleu à 45 °C en rouge par défaut). Taille et espacement des flèches au même endroit.
- **Visibilité** : `HandDissolve` publie ses trous dans les globales de shader `DISSOLVE_SOURCE_0/1` (`project.godot`). Les tuyaux sont toujours visibles dans l'éditeur ; `always_visible` les montre aussi en jeu, pour déboguer (les murs les cachent quand même).
- **Démo** : `scenes/effects/pipe_demo.tscn`, sur PC, avec 7 postes (touches 1 à 7) : tuyaux cachés dans les murs (maintenir le clic droit sur le mur pour creuser), échelle des températures, vitesses, refroidissement le long d'un tuyau, coudes et courbes, vanne changée en jeu (`pipe_demo_valve.gd`), et un petit circuit foyer → caldarium → tepidarium, aqueduc → frigidarium.
