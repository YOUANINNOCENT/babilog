"""Tests du service IA BabiLogis : python -m pytest -q"""
from fastapi.testclient import TestClient
from google.genai import types

from app.agent import AgentDeepSeek, AgentGemini, AgentGroq, Assistant, analyser
from app.main import app, etat


def client():
    return TestClient(app)


def test_sante_et_estimation():
    with client() as c:
        assert c.get("/sante").json()["statut"] == "ok"
        r = c.post("/estimer", json={"commune": "Cocody", "type": "Appartement", "pieces": 3}).json()
        assert r["estimation_min"] < r["estimation_centrale"] < r["estimation_max"]
        assert r["source"] == "modele"
        # contrat attendu par le serveur Dart
        assert {"estimation_min", "estimation_max"} <= r.keys()


def test_cocody_plus_cher_que_abobo():
    with client() as c:
        e = lambda com: c.post("/estimer", json={"commune": com, "type": "Appartement", "pieces": 3}).json()["estimation_centrale"]
        assert e("Cocody") > e("Abobo")


def test_commune_sans_donnees_avertit():
    with client() as c:
        r = c.post("/estimer", json={"commune": "Treichville", "type": "Studio", "pieces": 1}).json()
        assert r["fiabilite"] == "faible" and "avertissement" in r


def test_validation():
    with client() as c:
        assert c.post("/estimer", json={"commune": "Paris", "type": "Studio", "pieces": 1}).status_code == 422
        assert c.post("/estimer", json={"commune": "Cocody", "type": "Studio", "pieces": 0}).status_code == 422
        assert c.post("/verdict", json={"commune": "Cocody", "type": "Studio", "pieces": 1}).status_code == 422


def test_verdict():
    with client() as c:
        bas = c.post("/verdict", json={"commune": "Yopougon", "type": "Appartement", "pieces": 3, "loyer": 50_000}).json()
        haut = c.post("/verdict", json={"commune": "Yopougon", "type": "Appartement", "pieces": 3, "loyer": 900_000}).json()
        assert bas["verdict"] == "bonne_affaire" and haut["verdict"] == "au_dessus"


def test_analyse_du_langage():
    a = analyser("Je cherche un 2 chambres salon à Riviera Palmeraie sous 250k")
    assert a["commune"] == "Cocody" and a["pieces"] == 3 and a["budget_max"] == 250_000
    a = analyser("450 000 pour une villa 4 pièces à Bingerville, c'est cher ?")
    assert a["intention"] == "evaluer" and a["loyer"] == 450_000 and a["type_logement"] == "villa"
    assert analyser("studio à Port-Bouët")["commune"] == "Port-Bouët"
    assert analyser("appartement aux Deux Plateaux")["commune"] == "Cocody"


def test_agent_regles():
    with client() as c:
        r = c.post("/agent/discuter", json={"message": "combien pour un 3 pièces à Marcory ?"}).json()
        assert "Marcory" in r["reponse"] and r["outils"][0]["outil"] == "estimer_loyer"
        r = c.post("/agent/discuter", json={"message": "un 3 pièces à Cocody sous 300 000"}).json()
        assert r["annonces"] and all(a["loyer"] <= 300_000 for a in r["annonces"])


class FauxGemini:
    """Simule l'API Gemini : 1er tour = appel d'outil, 2e tour = réponse texte."""

    def __init__(self):
        self.appels = []
        self.models = self

    def generate_content(self, model, contents, config):
        self.appels.append(contents)
        if len(self.appels) == 1:
            fc = types.FunctionCall(name="evaluer_prix", args={"commune": "Cocody", "type_logement": "appartement",
                                                               "pieces": 3, "loyer": 600000})
            return types.GenerateContentResponse(candidates=[types.Candidate(
                content=types.Content(role="model", parts=[types.Part(function_call=fc)]))])
        retour = contents[-1].parts[0].function_response.response["resultat"]
        texte = f"C'est {retour['verdict_libelle'].lower()} (estimation {retour['estimation_centrale']} FCFA)."
        return types.GenerateContentResponse(candidates=[types.Candidate(
            content=types.Content(role="model", parts=[types.Part(text=texte)]))])


def test_agent_gemini_boucle_outils():
    with client():
        faux = FauxGemini()
        agent = AgentGemini(etat["outils"], client=faux, modele="faux-modele")
        r = agent.discuter("600 000 pour un 3 pièces à Cocody, c'est cher ?")
        assert r["outils"][0]["outil"] == "evaluer_prix" and r["outils"][0]["ok"]
        assert "au-dessus" in r["reponse"]
        assert len(faux.appels) == 2


def test_repli_si_gemini_plante():
    class Casse:
        modele = "x"

        def discuter(self, *a, **k):
            raise RuntimeError("quota")

    with client():
        r = Assistant(etat["outils"], agent_llm=Casse()).discuter("combien un studio à Abobo ?")
        assert r["moteur"].startswith("règles") and "note" in r


class FauxHttp:
    """Simule l'API DeepSeek / Groq (/chat/completions) : 1er tour = tool_call, 2e tour = texte."""

    def __init__(self):
        self.corps = []

    def post(self, url, headers, json):
        self.corps.append(json)
        n = len(self.corps)

        class R:
            status_code = 200

            def __init__(self, d):
                self._d = d

            def json(self):
                return self._d

        if n == 1:
            appel = {"id": "appel_1", "type": "function", "function": {"name": "estimer_loyer",
                     "arguments": '{"commune": "Yopougon", "type_logement": "studio", "pieces": 1}'}}
            return R({"choices": [{"message": {"role": "assistant", "content": "", "tool_calls": [appel]}}]})
        resultat = __import__("json").loads(json["messages"][-1]["content"])
        return R({"choices": [{"message": {"role": "assistant",
                                           "content": f"Environ {resultat['estimation_centrale']} FCFA."}}]})


def test_agent_deepseek_boucle_outils():
    with client():
        faux = FauxHttp()
        agent = AgentDeepSeek(etat["outils"], client=faux, modele="deepseek-flash", cle="test", url="https://exemple")
        r = agent.discuter("combien un studio à Yopougon ?")
        assert r["outils"][0]["outil"] == "estimer_loyer" and r["outils"][0]["ok"]
        assert r["reponse"].startswith("Environ") and r["moteur"] == "deepseek (deepseek-flash)"
        dernier = faux.corps[-1]["messages"]
        assert dernier[-2]["tool_calls"][0]["id"] == "appel_1" and dernier[-1]["role"] == "tool"
        assert faux.corps[0]["tools"][0]["type"] == "function"


def test_agent_groq_boucle_outils():
    with client():
        faux = FauxHttp()
        agent = AgentGroq(etat["outils"], client=faux, modele="openai/gpt-oss-120b", cle="test")
        r = agent.discuter("combien un studio à Yopougon ?")
        assert r["outils"][0]["outil"] == "estimer_loyer" and r["outils"][0]["ok"]
        assert r["moteur"] == "groq (openai/gpt-oss-120b)"
        assert agent.url == "https://api.groq.com/openai/v1/chat/completions"
