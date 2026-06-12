import urllib.parse
import requests
import re
import json
from datetime import datetime
from youtube_transcript_api import YouTubeTranscriptApi

class YouTubeMonitor:
    def __init__(self, analyzer, db, config_path="config.json"):
        self.analyzer = analyzer
        self.db = db
        self.config_path = config_path
        self.queries = []
        self.max_results = 10
        self._load_config()

    def _load_config(self):
        try:
            with open(self.config_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
                self.queries = config.get('queries', [])
                self.max_results = config.get('youtube_max_results', 10)
        except Exception:
            pass

    def get_transcript_snippet(self, video_id):
        """
        Descarga los subtítulos del video e intenta extraer un fragmento relevante 
        que contenga las palabras clave monitoreadas.
        """
        try:
            # Intentar obtener la transcripción en español, con inglés como alternativa
            transcript_list = YouTubeTranscriptApi.get_transcript(video_id, languages=['es', 'es-419', 'en'])
            
            full_text = " ".join([t['text'] for t in transcript_list])
            
            # Buscar dónde ocurren nuestras palabras clave
            keywords = ["jesús maría", "jesus maria", "jesús gálvez", "jesus galvez", "alcalde gálvez", "alcalde galvez"]
            lower_text = full_text.lower()
            
            best_snippet = ""
            for kw in keywords:
                idx = lower_text.find(kw)
                if idx != -1:
                    # Extraer alrededor de la coincidencia (150 caracteres antes y después)
                    start = max(0, idx - 120)
                    end = min(len(full_text), idx + len(kw) + 120)
                    best_snippet = "..." + full_text[start:end].strip() + "..."
                    break
            
            # Si no hay coincidencia de palabras clave, tomar los primeros 250 caracteres
            if not best_snippet:
                best_snippet = full_text[:250] + "..." if len(full_text) > 250 else full_text
                
            return full_text, best_snippet
        except Exception as e:
            # Las razones más comunes son que los subtítulos estén desactivados en el video
            return "", "Transcripción no disponible (desactivada por el creador)."

    def search_videos(self, query):
        """
        Busca videos en YouTube por palabra clave usando scraping de ytInitialData.
        """
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept-Language": "es-419,es;q=0.9"
        }
        encoded_query = urllib.parse.quote(query)
        # sp=CAI%253D ordena por fecha de carga (los más recientes primero)
        url = f"https://www.youtube.com/results?search_query={encoded_query}&sp=CAI%253D"
        
        videos = []
        try:
            r = requests.get(url, headers=headers, timeout=15)
            if r.status_code != 200:
                print(f"[YouTubeMonitor] HTTP Error {r.status_code} al buscar '{query}'")
                return []
                
            # Buscar el objeto JSON ytInitialData en la respuesta HTML
            pattern = r'ytInitialData\s*=\s*({.+?});'
            match = re.search(pattern, r.text)
            
            if match:
                try:
                    data = json.loads(match.group(1))
                    contents = data['contents']['twoColumnSearchResultRenderer']['primaryContents']['sectionListRenderer']['contents']
                    
                    # El primer item suele ser itemSectionRenderer
                    item_section = contents[0]['itemSectionRenderer']['contents']
                    for item in item_section:
                        if 'videoRenderer' in item:
                            vr = item['videoRenderer']
                            video_id = vr['videoId']
                            title = vr['title']['runs'][0]['text']
                            channel = vr['ownerText']['runs'][0]['text']
                            
                            published_date = "Reciente"
                            if 'publishedTimeText' in vr:
                                published_date = vr['publishedTimeText']['simpleText']
                                
                            description = ""
                            if 'detailedMetadataSnippets' in vr:
                                description = vr['detailedMetadataSnippets'][0]['snippetText']['runs'][0]['text']
                            elif 'descriptionSnippet' in vr:
                                description = vr['descriptionSnippet']['runs'][0]['text']
                                
                            videos.append({
                                'video_id': video_id,
                                'title': title,
                                'channel': channel,
                                'published_date': published_date,
                                'description': description
                            })
                except Exception as e:
                    print(f"[YouTubeMonitor] Error decodificando ytInitialData: {str(e)}")
            
            # Fallback básico con Regex si no pudimos extraer el JSON
            if not videos:
                matches = re.findall(r'/watch\?v=([a-zA-Z0-9_-]{11})', r.text)
                seen = set()
                video_ids = [x for x in matches if not (x in seen or seen.add(x))][:self.max_results]
                for v_id in video_ids:
                    videos.append({
                        'video_id': v_id,
                        'title': f"Video de YouTube {v_id}",
                        'channel': "Desconocido",
                        'published_date': "Reciente",
                        'description': "Monitoreado vía regex alternativo."
                    })
                    
        except Exception as e:
            print(f"[YouTubeMonitor] Error al realizar scraping de YouTube para '{query}': {str(e)}")
            
        return videos[:self.max_results]

    def monitor(self):
        """
        Ejecuta el monitoreo de YouTube para todas las consultas.
        Retorna la lista de nuevos videos relevantes insertados.
        """
        new_videos = []
        
        for query in self.queries:
            print(f"[YouTubeMonitor] Buscando videos de YouTube para: {query}")
            video_list = self.search_videos(query)
            print(f"[YouTubeMonitor] Se encontraron {len(video_list)} videos potenciales.")
            
            for video in video_list:
                video_id = video['video_id']
                
                # Evitar duplicados
                if self.db.exists_youtube_video(video_id):
                    continue
                
                # Obtener transcripción del video
                print(f"  [~] Descargando transcripción para video: {video_id}...")
                full_transcript, snippet = self.get_transcript_snippet(video_id)
                
                # Verificar relevancia
                text_to_analyze = f"{video['title']} {video['description']} {full_transcript}"
                relevance = self.analyzer.check_relevance(text_to_analyze, video['title'])
                
                if relevance == 0:
                    # Si el video no contiene menciones al distrito o alcalde, descartar
                    continue
                
                # Analizar sentimiento
                sentiment, sentiment_score = self.analyzer.analyze_sentiment(text_to_analyze)
                
                video_data = {
                    'video_id': video_id,
                    'query': query,
                    'title': video['title'],
                    'channel': video['channel'],
                    'published_date': video['published_date'],
                    'description': video['description'],
                    'transcript_snippet': snippet,
                    'sentiment': sentiment,
                    'sentiment_score': sentiment_score,
                    'relevance': relevance,
                    'scraped_at': datetime.now().isoformat()
                }
                
                self.db.insert_youtube_video(video_data)
                new_videos.append(video_data)
                print(f"  [+] Nuevo video: {video['title']} ({sentiment})")
                
        return new_videos
