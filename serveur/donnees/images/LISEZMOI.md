# Images BabiLogis

Toutes les images de la plateforme sont dans ce dossier ; la base de données (`../babilogis.sqlite`,
table `photos`) enregistre pour chacune : l'annonce, le type de logement, le chemin du fichier,
l'origine (photo de l'annonceur ou illustration), l'auteur et la licence.

```
images/
  illustrations/                photos d'illustration libres de droits (CC0, CC BY, CC BY-SA)
    studio/  appartement/  villa/
    manifeste.json              auteur, licence et lien d'origine de chaque photo
  annonces/<référence>/         vraies photos envoyées par les propriétaires et agences
```

- Remplir les illustrations : `python3 outils/collecter_images.py` (dans `serveur/`, avec internet),
  puis redémarrer le serveur.
- Les images sont servies par le serveur sur `http://127.0.0.1:8000/images/...`.
