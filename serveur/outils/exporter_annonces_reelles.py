"""Prépare les vraies annonces (Blocs 1 et 2) pour le serveur Dart.

Entrées :
  - bloc1/annonces_propres.csv        (annonces nettoyées)
  - bloc2/annonces_avec_verdict.csv   (estimation du modèle, calculée hors échantillon)
Sortie :
  - serveur/donnees/annonces_reelles.json  (lu par le serveur Dart au premier démarrage)

Utilisation :
  python3 outils/exporter_annonces_reelles.py ~/Desktop/"donnees 1"
"""
import json
import random
import re
import sys
import unicodedata
from pathlib import Path

import pandas as pd

QUARTIERS_CONNUS = {
    "Abobo": ["Abobo Gare", "Avocatier", "PK 18", "Abobo Baoulé"],
    "Bingerville": ["Bingerville Centre", "Akandjé", "Feh Kessé"],
    "Cocody": ["Angré", "Riviera 3", "II Plateaux", "Riviera Palmeraie", "Blockhaus", "Danga"],
    "Koumassi": ["Remblais", "Koumassi Campement", "Sicogi"],
    "Marcory": ["Zone 4", "Biétry", "Anoumabo", "Marcory Résidentiel"],
    "Plateau": ["Plateau Centre", "Indénié"],
    "Port-Bouët": ["Vridi", "Gonzagueville", "Adjouffou"],
    "Songon": ["Songon Agban", "Songon Kassemblé"],
    "Yopougon": ["Niangon", "Sideci", "Selmer", "Toits Rouges"],
}
SYNONYMES = {"deux plateaux": "II Plateaux", "2 plateaux": "II Plateaux", "ii plateaux": "II Plateaux",
             "plateaux": "II Plateaux", "pk18": "PK 18", "kassemble": "Songon Kassemblé", "angre": "Angré",
             "bietry": "Biétry", "feh kesse": "Feh Kessé", "akandje": "Akandjé", "zone": "Zone 4"}
ACCENTS = {"Angre": "Angré", "Chateau": "Château", "Kesse": "Kessé", "Bietry": "Biétry", "Akandje": "Akandjé",
           "Cite": "Cité", "Eme": "ème", "Bouet": "Bouët", "Rivièra": "Riviera"}
EQUIPEMENTS = {"climatisation": "Climatisation", "groupe_electrogene": "Groupe électrogène", "parking": "Parking",
               "gardien": "Gardien", "forage": "Forage", "piscine": "Piscine", "jardin": "Jardin",
               "terrasse": "Terrasse", "ascenseur": "Ascenseur"}
SITES = {"mydari": "mydari.com", "coinafrique": "ci.coinafrique.com", "caza": "caza.ci", "immooz": "immooz.com",
         "yecherch": "yecherch.com", "immo_ci": "immo.ci", "classeur_v13": "ivoiredomi.ci / immo.ci"}


def cle(s: str) -> str:
    s = "".join(c for c in unicodedata.normalize("NFD", str(s)) if unicodedata.category(c) != "Mn")
    return re.sub(r"[^a-z0-9 ]", " ", s.lower()).strip()


def quartier_propre(commune: str, q) -> str:
    if not isinstance(q, str) or not q.strip():
        return "Non précisé"
    k = re.sub(r"\s+", " ", cle(q))
    for nom in QUARTIERS_CONNUS.get(commune, []):
        if cle(nom) == k:
            return nom
    if k in SYNONYMES:
        return SYNONYMES[k]
    nom = " ".join(m if m.isupper() and len(m) <= 3 else m.capitalize() for m in q.split())
    for faux, juste in ACCENTS.items():
        nom = re.sub(rf"\b{faux}\b", juste, nom)
    return nom


def titre_propre(t: str) -> str:
    t = re.sub(r"^\s*\d+\s*/\s*\d+\s*", "", str(t))                       # compteur de photos
    t = re.sub(r"^\s*\d+\s+[\d\s]+(XOF|FCFA|CFA)\s*(Négociable)?\s*", "", t)  # « 2 4 800 000 XOF »
    t = re.sub(r"[\d\s]{4,}\s*(FCFA|XOF|CFA)\s*(/\s*mois)?", "", t)
    t = re.sub(r"\s*Abidjan, Côte d'Ivoire.*$", "", t)
    t = re.sub(r"\s+", " ", t).strip(" -–|,")
    return t[:160]


def type_dart(t: str, pieces: int) -> str:
    return {"villa": "Villa", "appartement": "Appartement", "studio": "Studio"}.get(
        t, "Studio" if pieces <= 1 else "Appartement")


def arrondir(v: float) -> int:
    return int(round(v / 5000) * 5000)


def main(dossier: Path, sortie: Path) -> None:
    a = pd.read_csv(dossier / "bloc1" / "annonces_propres.csv")
    v = pd.read_csv(dossier / "bloc2" / "annonces_avec_verdict.csv")
    assert (a["id"] == v["id"]).all(), "Les deux fichiers ne sont pas alignés : relancez les notebooks 1 puis 2."
    a["estimation"] = v["estimation"]
    a["verdict"] = v["verdict"]

    r = random.Random(2026)
    lignes = list(a.itertuples())
    r.shuffle(lignes)
    # BL-1004 et BL-1009 servent d'exemples de signalement « prix trop élevé » : on y place des annonces au-dessus
    hauts = [i for i, x in enumerate(lignes) if x.verdict == "au_dessus"]
    for cible, src in zip((3, 8), hauts[:2]):
        lignes[cible], lignes[src] = lignes[src], lignes[cible]

    annonces = []
    for n, x in enumerate(lignes):
        pieces = max(1, min(int(x.pieces), 20))
        eqs = [e for e in str(x.equipements).split(";") if e and e != "nan"]
        titre = titre_propre(x.titre)
        site = SITES.get(x.site, x.site)
        description = (f"{titre}. " if len(titre) > 14 else "") \
            + ("Haut standing. " if "haut_standing" in eqs else "") \
            + f"Annonce publique collectée sur {site} en octobre 2026 (données de la soutenance BabiLogis). " \
            + f"Annonce d'origine : {x.url}"
        annonces.append({
            "reference": f"BL-{1001 + n}",
            "commune": x.commune,
            "quartier": quartier_propre(x.commune, x.quartier),
            "type": type_dart(x.type_logement, pieces),
            "pieces": pieces,
            "chambres": max(1, pieces - 1),
            "salles_bain": 2 if pieces >= 4 else 1,
            "meuble": bool(x.meuble),
            "loyer": int(x.prix_fcfa),
            "estimation_min": arrondir(x.estimation * 0.85),
            "estimation_max": arrondir(x.estimation * 1.15),
            "equipements": sorted({EQUIPEMENTS[e] for e in eqs if e in EQUIPEMENTS}),
            "description": description,
            "source": site,
            "url": x.url,
            "age_jours": r.randint(1, 45),
        })
    sortie.parent.mkdir(parents=True, exist_ok=True)
    sortie.write_text(json.dumps({"version": 1, "annonces": annonces}, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{len(annonces)} annonces écrites dans {sortie}")


if __name__ == "__main__":
    dossier = Path(sys.argv[1] if len(sys.argv) > 1 else Path.home() / "Desktop" / "donnees 1").expanduser()
    main(dossier, Path(__file__).resolve().parent.parent / "donnees" / "annonces_reelles.json")
