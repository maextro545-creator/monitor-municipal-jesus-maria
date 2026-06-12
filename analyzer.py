import json
import re

class ContentAnalyzer:
    def __init__(self, config_path="config.json"):
        self.config_path = config_path
        self._load_config()

    def _load_config(self):
        try:
            with open(self.config_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
                self.pos_words = config.get('sentiment_positive_words', [])
                self.neg_words = config.get('sentiment_negative_words', [])
                self.queries = config.get('queries', [])
        except Exception:
            self.pos_words = []
            self.neg_words = []
            self.queries = []

    def clean_text(self, text):
        if not text:
            return ""
        # Convertir a minúsculas y quitar caracteres especiales básicos
        text = text.lower()
        text = re.sub(r'[^\w\sáéíóúüñ]', ' ', text)
        return text

    def analyze_sentiment(self, text):
        """
        Analiza el sentimiento basándose en conteo de palabras clave.
        Retorna (sentimiento, score)
        """
        cleaned = self.clean_text(text)
        words = cleaned.split()
        
        pos_count = 0
        neg_count = 0
        
        for word in words:
            # Comprobar si alguna de las raíces de palabras positivas coincide
            for pos in self.pos_words:
                if pos in word:
                    pos_count += 1
                    break
            # Comprobar raíces de palabras negativas
            for neg in self.neg_words:
                if neg in word:
                    neg_count += 1
                    break
        
        total = pos_count + neg_count
        if total == 0:
            score = 0.0
            sentiment = "neutral"
        else:
            score = (pos_count - neg_count) / total
            if score > 0.15:
                sentiment = "positivo"
            elif score < -0.15:
                sentiment = "negativo"
            else:
                sentiment = "neutral"
                
        return sentiment, round(score, 2)

    def check_relevance(self, text, title=""):
        """
        Verifica si el contenido realmente pertenece al tema del monitoreo.
        Retorna 1 si es relevante, 0 de lo contrario.
        """
        combined = self.clean_text(f"{title} {text}")
        
        # Debe contener al menos algunos términos relacionados a Jesús María o Jesús Gálvez
        keywords = ["jesus maria", "jesús maría", "jesús gálvez", "jesus galvez", "alcalde gálvez", "alcalde galvez"]
        for kw in keywords:
            if kw in combined:
                return 1
        return 0
