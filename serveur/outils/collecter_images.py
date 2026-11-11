"""Collecte de photos d'INTÉRIEURS de logements (studio, appartement, maison/villa), libres de droits,
sans répétition. Les photos de lits et de matelas sont exclues.

Sources : Wikimedia Commons (https://commons.wikimedia.org, rapide) puis Openverse (https://openverse.org),
images sous licence Creative Commons. Seules les licences qui autorisent la réutilisation, y compris commerciale,
sont gardées : CC0, CC BY, CC BY-SA. L'auteur, la licence et le lien d'origine sont enregistrés et affichés.

Pas de photos de sites d'annonces ni de Pinterest : elles appartiennent à leurs auteurs (agences,
photographes) et montrent d'autres logements. Pour vos photos ou des photos autorisées : importer_images.py.

Pas de répétition : une photo n'est gardée que si elle est nouvelle (même identifiant, même lien d'origine,
même fichier ou image presque identique → refusée), avec au plus 2 photos par auteur.

Utilisation (sur le Mac, avec internet ; rien à installer) :
    cd ~/Desktop/babilog/serveur
    python3 outils/collecter_images.py                    # 30 photos par type
    python3 outils/collecter_images.py --nombre 50
    python3 outils/collecter_images.py --recommencer      # efface les anciennes photos téléchargées
    python3 outils/collecter_images.py --abidjan          # uniquement des photos situées à Abidjan / Côte d'Ivoire

Résultat : donnees/images/illustrations/<studio|appartement|villa>/*.jpg + manifeste.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import ssl
import struct
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://api.openverse.org/v1/images/"
COMMONS = "https://commons.wikimedia.org/w/api.php"
AGENT = "BabiLogis/1.0 (projet etudiant, soutenance Developpeur Data IA, Abidjan)"
LICENCES = "cc0,by,by-sa"
RACINE = Path(__file__).resolve().parent.parent / "donnees" / "images" / "illustrations"
SIGNATURES = (b"\xff\xd8\xff", b"\x89PNG", b"RIFF")
MAX_PAR_AUTEUR = 2
SEUIL_PRESQUE_IDENTIQUE = 6          # bits différents sur 64 (empreinte visuelle)

RECHERCHES = {
    "studio": ["studio apartment interior", "small apartment living room", "studio apartment kitchenette",
               "compact living room", "tiny apartment interior", "small modern kitchen", "studio flat interior",
               "small living room sofa"],
    "appartement": ["modern apartment living room", "apartment interior", "modern kitchen interior",
                    "apartment dining room", "living room interior design", "open plan kitchen living room",
                    "modern lounge interior", "apartment lounge sofa"],
    "villa": ["luxury living room", "luxury house interior", "villa interior", "modern house living room",
              "luxury kitchen interior", "luxury dining room", "modern villa lounge", "house interior design"],
}
RECHERCHES_ABIDJAN = {
    "studio": ["Abidjan studio", "Abidjan appartement", "Abidjan apartment interior", "Cocody appartement"],
    "appartement": ["Abidjan appartement", "Abidjan apartment", "Abidjan salon", "Cocody résidence", "Abidjan résidence"],
    "villa": ["Abidjan villa", "Cocody villa", "Abidjan maison", "villa Côte d'Ivoire", "Ivory Coast house interior"],
}
LIEUX = {"abidjan", "cocody", "riviera", "marcory", "plateau", "yopougon", "koumassi", "treichville", "bingerville",
         "angré", "angre", "ivoire", "ivory", "ivoirien", "ivoirienne", "ivorian", "songon", "adjamé", "abobo"}
# Intérieur de logement : au moins un de ces mots dans le titre, la description ou les mots-clés…
MOTS_INTERIEUR = {"interior", "interiors", "indoor", "inside", "living", "lounge", "kitchen", "kitchenette", "dining",
                  "sofa", "couch", "furniture", "apartment", "flat", "condo", "studio", "villa", "house", "home",
                  "salon", "cuisine", "séjour", "intérieur", "appartement", "maison", "décoration", "decor", "design"}
# Exclus partout (titre, description ET mots-clés) : lits/matelas (demandé), salles de bain, personnes.
EXCLUS_FORTS = {
    "bed", "beds", "bedroom", "bedrooms", "mattress", "mattresses", "bunk", "crib", "cot", "pillow", "pillows",
    "duvet", "bedding", "lit", "matelas", "chambre", "couchette", "hostel", "dormitory",
    "bathroom", "toilet", "shower", "bathtub", "people", "person", "woman", "man", "girl", "boy", "child",
    "children", "baby", "selfie", "portrait", "wedding"}
# Exclus seulement s'ils sont dans le TITRE ou la DESCRIPTION (les mots-clés Flickr sont trop nombreux).
EXCLUS_TITRE = {
    "exterior", "facade", "façade", "street", "aerial", "garden", "museum", "church", "cathedral", "castle", "palace",
    "mansion", "historic", "victorian", "1800s", "1900s", "abandoned", "ruin", "ruins", "demolition", "hotel", "office",
    "school", "hospital", "station", "shop", "store", "restaurant", "bar", "cafe", "café", "painting", "drawing",
    "sketch", "render", "rendering", "3d", "cgi", "miniature", "toy", "dollhouse", "lego", "exhibit", "exhibition",
    "dog", "cat", "party", "christmas", "halloween", "floorplan", "blueprint", "market", "car", "boat"}
MOTS_EXCLUS = EXCLUS_FORTS | EXCLUS_TITRE      # (compatibilité)

# ── Réseau ────────────────────────────────────────────────────────────────


def _contexte_ssl() -> ssl.SSLContext:
    """Certificats HTTPS : certifi s'il est installé, sinon ceux de macOS (/etc/ssl/cert.pem)."""
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        pass
    for chemin in ("/etc/ssl/cert.pem", "/usr/local/etc/openssl/cert.pem", "/opt/homebrew/etc/openssl@3/cert.pem"):
        if os.path.exists(chemin):
            return ssl.create_default_context(cafile=chemin)
    return ssl.create_default_context()


SSL = _contexte_ssl()


def _get(url: str, timeout: int = 30) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": AGENT, "Accept": "*/*"})
    with urllib.request.urlopen(req, timeout=timeout, context=SSL) as r:
        return r.read()


SOURCE = "commons"          # commons (Wikimedia Commons, rapide) puis openverse ; choisi par --source


def _openverse(requete: str, page: int) -> list[dict]:
    params = urllib.parse.urlencode({"q": requete, "license": LICENCES, "category": "photograph",
                                     "mature": "false", "page_size": 20, "page": page})
    for essai in range(1, 3):
        try:
            return json.loads(_get(f"{API}?{params}", timeout=25)).get("results", [])
        except (urllib.error.URLError, OSError, ValueError) as e:
            if essai == 2:
                print(f"   ! Openverse « {requete} » (page {page}) : {e}")
                return []
            time.sleep(3)
    return []


def _sans_html(t: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", t or "")).strip()


def _licence_commons(nom: str) -> tuple[str, str] | None:
    """Licences acceptées sur Wikimedia Commons → (code, version) au format Openverse."""
    n = (nom or "").strip().lower()
    if n in ("cc0", "cc0 1.0", "cc-zero") or n.startswith("public domain") or n == "pd":
        return ("cc0", "")
    m = re.match(r"cc[ -]by(-sa)?[ -]?([0-9.]+)?", n)
    if m:
        return ("by-sa" if m.group(1) else "by", m.group(2) or "")
    return None


def _commons(requete: str, page: int) -> list[dict]:
    """Wikimedia Commons : fichiers (photos) libres, avec auteur, licence et catégories."""
    params = urllib.parse.urlencode({
        "action": "query", "format": "json", "generator": "search", "gsrnamespace": 6,
        "gsrsearch": f"{requete} filetype:bitmap", "gsrlimit": 20, "gsroffset": (page - 1) * 20,
        "prop": "imageinfo", "iiprop": "url|size|mime|extmetadata", "iiurlwidth": 1280})
    try:
        d = json.loads(_get(f"{COMMONS}?{params}", timeout=30))
    except (urllib.error.URLError, OSError, ValueError) as e:
        print(f"   ! Commons « {requete} » (page {page}) : {e}")
        return []
    res = []
    for pg in (d.get("query", {}).get("pages", {}) or {}).values():
        info = (pg.get("imageinfo") or [{}])[0]
        meta = info.get("extmetadata", {}) or {}
        val = lambda k: (meta.get(k) or {}).get("value", "")
        lic = _licence_commons(_sans_html(val("LicenseShortName")))
        if not lic or info.get("mime") not in ("image/jpeg", "image/png", "image/webp"):
            continue
        titre = re.sub(r"^File:|\.[a-zA-Z]{3,4}$", "", pg.get("title", "")).replace("_", " ")
        res.append({
            "id": f"commons:{pg.get('pageid')}", "title": titre, "description": _sans_html(val("ImageDescription"))[:400],
            "tags": [{"name": c} for c in val("Categories").split("|") if c],
            "creator": _sans_html(val("Artist"))[:120] or "Auteur inconnu",
            "license": lic[0], "license_version": lic[1],
            "width": info.get("width"), "height": info.get("height"),
            "url": info.get("thumburl") or info.get("url"),
            "foreign_landing_url": info.get("descriptionurl"), "source": "wikimedia commons",
        })
    return res


def rechercher(requete: str, page: int = 1) -> list[dict]:
    if SOURCE == "openverse":
        return _openverse(requete, page)
    res = _commons(requete, page)
    if not res and SOURCE == "tout":
        res = _openverse(requete, page)
    return res


# ── Filtres ───────────────────────────────────────────────────────────────


def _tokens(texte: str) -> set[str]:
    texte = texte.lower().replace("côte d'ivoire", "ivoire").replace("côte d’ivoire", "ivoire")
    return set(re.findall(r"[a-zàâçéèêëîïôûùüÿœ0-9]+", texte))


def _mots(r: dict) -> set[str]:
    return _tokens(" ".join([r.get("title") or "", r.get("description") or ""]
                            + [t.get("name", "") for t in (r.get("tags") or []) if isinstance(t, dict)]))


def raison_refus(r: dict, abidjan: bool = False) -> str | None:
    """None si la photo convient, sinon la raison du refus."""
    tous = _mots(r)
    titre = _tokens(f"{r.get('title') or ''} {r.get('description') or ''}")
    if tous & EXCLUS_FORTS:
        return "lit, salle de bain ou personne"
    if titre & EXCLUS_TITRE:
        return "hors sujet"
    if abidjan and not (tous & LIEUX):
        return "pas à Abidjan"
    if not (tous & MOTS_INTERIEUR):
        return "pas un intérieur de logement"
    return None


def est_interieur(r: dict, abidjan: bool = False) -> bool:
    """Intérieur de logement, sans lit ni matelas (et situé à Abidjan si demandé)."""
    return raison_refus(r, abidjan) is None


def libelle_licence(r: dict) -> str:
    lic = (r.get("license") or "").upper()
    if lic == "CC0":
        return "CC0 (domaine public)"
    if lic == "PDM":
        return "Domaine public"
    return f"CC {lic.replace('-', ' ').replace(' ', '-')} {r.get('license_version') or ''}".strip()


def _titre_normalise(t: str) -> str:
    return re.sub(r"[^a-z]+", " ", (t or "").lower()).strip()

# ── Images ────────────────────────────────────────────────────────────────


def redimensionner(chemin: Path) -> None:
    """Réduit à 1280 px (sips sur macOS, sinon Pillow s'il est installé, sinon rien)."""
    if shutil.which("sips"):
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "80", "-Z", "1280",
                        str(chemin), "--out", str(chemin)], capture_output=True)
        return
    try:
        from PIL import Image
        with Image.open(chemin) as im:
            im = im.convert("RGB")
            im.thumbnail((1280, 1280))
            im.save(chemin, "JPEG", quality=80, optimize=True)
    except Exception:
        pass


def _gris_8x8(chemin: Path) -> list[int] | None:
    """64 niveaux de gris d'une miniature 8×8 (sips → BMP sur macOS, ou Pillow)."""
    try:
        from PIL import Image
        with Image.open(chemin) as im:
            return list(im.convert("L").resize((8, 8)).getdata())
    except Exception:
        pass
    if not shutil.which("sips"):
        return None
    with tempfile.TemporaryDirectory() as tmp:
        bmp = Path(tmp) / "m.bmp"
        subprocess.run(["sips", "-s", "format", "bmp", "-z", "8", "8", str(chemin), "--out", str(bmp)], capture_output=True)
        if not bmp.exists():
            return None
        d = bmp.read_bytes()
        try:
            debut = struct.unpack_from("<I", d, 10)[0]
            largeur, hauteur = struct.unpack_from("<ii", d, 18)
            bpp = struct.unpack_from("<H", d, 28)[0]
        except struct.error:
            return None
        if bpp not in (24, 32) or largeur != 8 or abs(hauteur) != 8:
            return None
        octets, pas = bpp // 8, ((bpp * 8 + 31) // 32) * 4
        gris = []
        for y in range(8):
            ligne = (7 - y) if hauteur > 0 else y
            for x in range(8):
                i = debut + ligne * pas + x * octets
                b, g, r = d[i], d[i + 1], d[i + 2]
                gris.append((r * 299 + g * 587 + b * 114) // 1000)
        return gris


def empreinte_visuelle(chemin: Path) -> int | None:
    """Empreinte « average hash » : deux photos presque identiques ont presque la même empreinte."""
    g = _gris_8x8(chemin)
    if not g:
        return None
    moyenne = sum(g) / len(g)
    return sum(1 << i for i, v in enumerate(g) if v > moyenne)


def presque_identique(e: int | None, autres: list[int]) -> bool:
    return e is not None and any(bin(e ^ a).count("1") <= SEUIL_PRESQUE_IDENTIQUE for a in autres)

# ── Collecte ──────────────────────────────────────────────────────────────


def recommencer() -> None:
    """Supprime les photos téléchargées. Celles importées avec importer_images.py sont conservées."""
    for categorie in RECHERCHES:
        for f in (RACINE / categorie).glob("*.jpg"):
            if "-import-" not in f.name:
                f.unlink()
    m = RACINE / "manifeste.json"
    if m.exists():
        d = json.loads(m.read_text(encoding="utf-8"))
        d["photos"] = [p for p in d.get("photos", []) if p.get("fournisseur") == "import"]
        m.write_text(json.dumps(d, ensure_ascii=False, indent=1), encoding="utf-8")


def _prochain_nom(dossier: Path, categorie: str) -> Path:
    i = 1
    while (dossier / f"{categorie}-{i:03d}.jpg").exists():
        i += 1
    return dossier / f"{categorie}-{i:03d}.jpg"


def collecter(nombre: int, abidjan: bool = False) -> list[dict]:
    manifeste_path = RACINE / "manifeste.json"
    deja = json.loads(manifeste_path.read_text(encoding="utf-8")) if manifeste_path.exists() else {"photos": []}
    photos = [p for p in deja.get("photos", []) if (RACINE.parent / p["fichier"]).exists()]
    # Ce qui est déjà présent ne doit pas revenir (toutes catégories confondues)
    ids = {p.get("id_source") for p in photos}
    liens = {p.get("lien_source") for p in photos if p.get("lien_source")}
    titres = {(_titre_normalise(p.get("titre", "")), p.get("auteur", "").lower()) for p in photos}
    contenus, visuelles = set(), []
    for p in photos:
        f = RACINE.parent / p["fichier"]
        contenus.add(p.get("sha256") or hashlib.sha256(f.read_bytes()).hexdigest())
        e = p.get("empreinte")
        e = int(e, 16) if e else empreinte_visuelle(f)
        if e is not None:
            visuelles.append(e)
    refus = {"filtre": 0, "doublon": 0, "taille": 0, "telechargement": 0, "reponses": 0}
    recherches = RECHERCHES_ABIDJAN if abidjan else RECHERCHES

    def enregistrer():
        manifeste_path.write_text(json.dumps({"source": "Wikimedia Commons / Openverse — licences CC0, CC BY, CC BY-SA",
                                              "photos": photos}, ensure_ascii=False, indent=1), encoding="utf-8")

    for categorie, requetes in recherches.items():
        dossier = RACINE / categorie
        dossier.mkdir(parents=True, exist_ok=True)
        n = sum(1 for p in photos if p["categorie"] == categorie)
        print(f"→ {categorie} : {n} déjà présentes, objectif {nombre}")
        for requete in requetes:
            page = 1
            while n < nombre and page <= 5:
                resultats = rechercher(requete, page)
                time.sleep(1.0)
                if not resultats:
                    break
                refus["reponses"] += len(resultats)
                for r in resultats:
                    if n >= nombre:
                        break
                    largeur, hauteur = r.get("width") or 0, r.get("height") or 0
                    if largeur < 640 or hauteur < 400 or largeur < hauteur:
                        refus["taille"] += 1
                        continue
                    if not est_interieur(r, abidjan):
                        refus["filtre"] += 1
                        continue
                    auteur = (r.get("creator") or "Auteur inconnu").strip()[:120]
                    cle_titre = (_titre_normalise(r.get("title") or ""), auteur.lower())
                    lien = r.get("foreign_landing_url") or r.get("url")
                    if (r.get("id") in ids or lien in liens or (cle_titre[0] and cle_titre in titres)
                            or sum(1 for p in photos if p["auteur"].lower() == auteur.lower()) >= MAX_PAR_AUTEUR):
                        refus["doublon"] += 1
                        continue
                    try:
                        donnees = _get(r["url"])
                    except (urllib.error.URLError, OSError, ValueError, KeyError):
                        refus["telechargement"] += 1
                        continue
                    if not donnees.startswith(SIGNATURES) or len(donnees) < 20_000:
                        refus["telechargement"] += 1
                        continue
                    sha = hashlib.sha256(donnees).hexdigest()
                    if sha in contenus:
                        refus["doublon"] += 1
                        continue
                    fichier = _prochain_nom(dossier, categorie)
                    fichier.write_bytes(donnees)
                    redimensionner(fichier)
                    e = empreinte_visuelle(fichier)
                    if presque_identique(e, visuelles):              # même photo, autre taille ou recadrage
                        fichier.unlink()
                        refus["doublon"] += 1
                        continue
                    photos.append({
                        "fichier": f"illustrations/{categorie}/{fichier.name}",
                        "categorie": categorie,
                        "titre": (r.get("title") or "").strip()[:160],
                        "auteur": auteur,
                        "licence": libelle_licence(r),
                        "lien_source": lien,
                        "fournisseur": r.get("source") or r.get("provider") or "",
                        "id_source": r["id"],
                        "sha256": sha,
                        "empreinte": f"{e:016x}" if e is not None else None,
                    })
                    ids.add(r["id"])
                    liens.add(lien)
                    titres.add(cle_titre)
                    contenus.add(sha)
                    if e is not None:
                        visuelles.append(e)
                    n += 1
                    print(f"   + {fichier.name}  ({photos[-1]['licence']}, {auteur})")
                page += 1
            if n >= nombre:
                break
        enregistrer()
    print(f"\n   Bilan : {refus['reponses']} résultats reçus · {refus['filtre']} écartés par les filtres · "
          f"{refus['taille']} trop petits ou en portrait · {refus['doublon']} doublons évités · "
          f"{refus['telechargement']} téléchargements impossibles")
    if refus["reponses"] == 0:
        print("   ⚠️ Aucune réponse : connexion internet coupée, ou services momentanément indisponibles.")
    return photos


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--nombre", type=int, default=30, help="photos par type de logement (défaut : 30, max 80)")
    p.add_argument("--recommencer", action="store_true", help="supprime les photos déjà téléchargées")
    p.add_argument("--abidjan", action="store_true", help="uniquement des photos situées à Abidjan / Côte d'Ivoire")
    p.add_argument("--source", choices=("commons", "openverse", "tout"), default="tout",
                   help="commons = Wikimedia Commons ; openverse ; tout = Commons puis Openverse (défaut)")
    args = p.parse_args()
    global SOURCE
    SOURCE = args.source
    if args.recommencer:
        recommencer()
        print("Anciennes photos téléchargées supprimées.")
    photos = collecter(max(1, min(args.nombre, 80)), abidjan=args.abidjan)
    par = {c: sum(1 for x in photos if x["categorie"] == c) for c in RECHERCHES}
    print(f"✓ {len(photos)} photos dans {RACINE}  ({', '.join(f'{k} : {v}' for k, v in par.items())})")
    if not photos:
        print("Aucune photo : vérifiez la connexion internet, puis relancez.")
        return 1
    print("Redémarrez le serveur (dart run bin/serveur.dart) : les photos sont importées dans la base au démarrage.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
