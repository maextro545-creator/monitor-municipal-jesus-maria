import urllib.parse
import feedparser
from bs4 import BeautifulSoup
from datetime import datetime
import time

class NewsMonitor:
    def __init__(self, analyzer, db, config_path="config.json"):
        self.analyzer = analyzer
        self.db = db
        self.config_path = config_path
        self.queries = []
        self.max_results = 20
        self._load_config()

    def _load_config(self):
        import json
        try:
            with open(self.config_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
                self.queries = config.get('queries', [])
                self.max_results = config.get('news_max_results', 20)
        except Exception:
            pass

    def clean_html(self, html_content):
        if not html_content:
            return ""
        soup = BeautifulSoup(html_content, "html.parser")
        return soup.get_text()

    def parse_date(self, date_str):
        # Intentar parsear la fecha de RSS (por ejemplo: "Fri, 12 Jun 2026 10:20:00 GMT")
        try:
            parsed = feedparser._parse_date(date_str)
            if parsed:
                return datetime.fromtimestamp(time.mktime(parsed)).isoformat()
        except Exception:
            pass
        return datetime.now().isoformat()

    def monitor(self):
        """
        Rastrea noticias para cada consulta configurada.
        Retorna la lista de nuevos artículos encontrados.
        """
        new_articles = []
        
        for query in self.queries:
            # Codificar la consulta para la URL. Usamos comillas para buscar la frase exacta si es necesario, 
            # pero Google News responde bien con la consulta codificada directa.
            encoded_query = urllib.parse.quote(f'"{query}"')
            rss_url = f"https://news.google.com/rss/search?q={encoded_query}&hl=es-419&gl=PE&ceid=PE:es"
            
            print(f"[NewsMonitor] Consultando Google News RSS para: {query}")
            try:
                feed = feedparser.parse(rss_url)
                
                # Limitar resultados
                entries = feed.entries[:self.max_results]
                print(f"[NewsMonitor] Se encontraron {len(entries)} entradas potenciales.")
                
                for entry in entries:
                    url = entry.link
                    
                    # Evitar duplicados si ya existe en la DB
                    if self.db.exists_news(url):
                        continue
                        
                    title = entry.title
                    source = entry.source.text if hasattr(entry, 'source') else "Prensa"
                    published_raw = entry.published if hasattr(entry, 'published') else ""
                    published_date = self.parse_date(published_raw)
                    
                    # Limpiar la descripción (suele contener HTML con enlaces)
                    summary_html = entry.description if hasattr(entry, 'description') else ""
                    summary = self.clean_html(summary_html)
                    
                    # Analizar relevancia y sentimiento
                    relevance = self.analyzer.check_relevance(summary, title)
                    if relevance == 0:
                        # Si no es muy relevante, saltar
                        continue
                        
                    sentiment, sentiment_score = self.analyzer.analyze_sentiment(f"{title} {summary}")
                    
                    article_data = {
                        'url': url,
                        'query': query,
                        'title': title,
                        'source': source,
                        'published_date': published_date,
                        'summary': summary,
                        'sentiment': sentiment,
                        'sentiment_score': sentiment_score,
                        'relevance': relevance,
                        'scraped_at': datetime.now().isoformat()
                    }
                    
                    self.db.insert_news(article_data)
                    new_articles.append(article_data)
                    print(f"  [+] Nueva noticia: {title} ({sentiment})")
                    
            except Exception as e:
                print(f"[NewsMonitor] Error al monitorear noticias para '{query}': {str(e)}")
                
        return new_articles
