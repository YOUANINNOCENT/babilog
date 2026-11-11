"""Importe dans la bibliothèque d'illustrations des photos que VOUS avez le droit d'utiliser :
vos propres photos, ou celles d'une agence qui vous a donné son autorisation (par écrit).

    cd ~/Desktop/babilog/serveur
    python3 outils/importer_images.py ~/Desktop/photos_villas --categorie villa \\
        --auteur "Agence X (Abidjan)" --licence "Utilisée avec l'autorisation de l'agence"

    python3 outils/importer_images.py ~/Desktop/mes_photos --categorie appartement --auteur "YOUAN Innocent" \\
        --licence "Photo personnelle"

Les fichiers sont copiés (et réduits à 1280 px) dans donnees/images/illustrations/<categorie>/ et ajoutés à
manifeste.json avec l'auteur et la mention de licence, affichés sous chaque photo. Redémarrez ensuite le serveur.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from collecter_images import RACINE, redimensionner  # noqa: E402

CATEGORIES = ("studio", "appartement", "villa")
EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".heic"}


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("dossier", help="dossier (ou fichier) contenant les photos")
    p.add_argument("--categorie", required=True, choices=CATEGORIES)
    p.add_argument("--auteur", required=True, help="auteur ou propriétaire des photos (affiché en crédit)")
    p.add_argument("--licence", required=True,
                   help="droit d'utilisation, ex. « Photo personnelle » ou « Utilisée avec l'autorisation de … »")
    p.add_argument("--lien", default="", help="lien d'origine (facultatif)")
    a = p.parse_args()

    source = Path(a.dossier).expanduser()
    fichiers = [source] if source.is_file() else sorted(f for f in source.iterdir() if f.suffix.lower() in EXTENSIONS)
    if not fichiers:
        print(f"Aucune image dans {source}")
        return 1
    manifeste_path = RACINE / "manifeste.json"
    manifeste = json.loads(manifeste_path.read_text(encoding="utf-8")) if manifeste_path.exists() else {"photos": []}
    photos = manifeste.setdefault("photos", [])
    dossier = RACINE / a.categorie
    dossier.mkdir(parents=True, exist_ok=True)
    n = 0
    for f in fichiers:
        numero = len(list(dossier.glob("*.jpg"))) + 1
        cible = dossier / f"{a.categorie}-import-{numero:03d}.jpg"
        while cible.exists():
            numero += 1
            cible = dossier / f"{a.categorie}-import-{numero:03d}.jpg"
        shutil.copy2(f, cible)
        redimensionner(cible)            # convertit aussi en JPEG (HEIC, PNG…) avec sips sur macOS
        photos.append({"fichier": f"illustrations/{a.categorie}/{cible.name}", "categorie": a.categorie,
                       "titre": f.stem, "auteur": a.auteur, "licence": a.licence, "lien_source": a.lien,
                       "fournisseur": "import", "id_source": f"import:{cible.name}"})
        n += 1
        print(f"   + {cible.name}  ({f.name})")
    manifeste_path.write_text(json.dumps(manifeste, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"\n✓ {n} photo(s) ajoutée(s) dans {dossier}. Redémarrez le serveur pour les importer dans la base.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
