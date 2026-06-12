import sqlite3
import os
import json
from datetime import datetime

class Database:
    def __init__(self, db_path="monitor.db"):
        self.db_path = db_path
        self._init_db()

    def _get_connection(self):
        return sqlite3.connect(self.db_path)

    def _init_db(self):
        with self._get_connection() as conn:
            cursor = conn.cursor()
            
            # Crear tabla de noticias
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS news (
                    url TEXT PRIMARY KEY,
                    query TEXT,
                    title TEXT NOT NULL,
                    source TEXT,
                    published_date TEXT,
                    summary TEXT,
                    sentiment TEXT,
                    sentiment_score REAL,
                    relevance INTEGER,
                    scraped_at TEXT
                )
            ''')
            
            # Crear tabla de videos de YouTube
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS youtube_videos (
                    video_id TEXT PRIMARY KEY,
                    query TEXT,
                    title TEXT NOT NULL,
                    channel TEXT,
                    published_date TEXT,
                    description TEXT,
                    transcript_snippet TEXT,
                    sentiment TEXT,
                    sentiment_score REAL,
                    relevance INTEGER,
                    scraped_at TEXT
                )
            ''')
            conn.commit()

    def insert_news(self, news_data):
        """
        Inserta o actualiza un artículo de noticias.
        news_data debe ser un diccionario con los campos correspondientes.
        """
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute('''
                INSERT OR REPLACE INTO news 
                (url, query, title, source, published_date, summary, sentiment, sentiment_score, relevance, scraped_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                news_data.get('url'),
                news_data.get('query'),
                news_data.get('title'),
                news_data.get('source'),
                news_data.get('published_date'),
                news_data.get('summary'),
                news_data.get('sentiment', 'neutral'),
                news_data.get('sentiment_score', 0.0),
                news_data.get('relevance', 1),
                news_data.get('scraped_at', datetime.now().isoformat())
            ))
            conn.commit()

    def insert_youtube_video(self, video_data):
        """
        Inserta o actualiza un video de YouTube.
        """
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute('''
                INSERT OR REPLACE INTO youtube_videos 
                (video_id, query, title, channel, published_date, description, transcript_snippet, sentiment, sentiment_score, relevance, scraped_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                video_data.get('video_id'),
                video_data.get('query'),
                video_data.get('title'),
                video_data.get('channel'),
                video_data.get('published_date'),
                video_data.get('description'),
                video_data.get('transcript_snippet'),
                video_data.get('sentiment', 'neutral'),
                video_data.get('sentiment_score', 0.0),
                video_data.get('relevance', 1),
                video_data.get('scraped_at', datetime.now().isoformat())
            ))
            conn.commit()

    def exists_news(self, url):
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute('SELECT 1 FROM news WHERE url = ?', (url,))
            return cursor.fetchone() is not None

    def exists_youtube_video(self, video_id):
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute('SELECT 1 FROM youtube_videos WHERE video_id = ?', (video_id,))
            return cursor.fetchone() is not None

    def get_all_data(self):
        """
        Retorna todo el contenido estructurado de la base de datos para exportarlo a JSON.
        """
        with self._get_connection() as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            
            # Obtener noticias
            cursor.execute('SELECT * FROM news ORDER BY published_date DESC, scraped_at DESC')
            news_rows = cursor.fetchall()
            news_list = [dict(row) for row in news_rows]
            
            # Obtener videos
            cursor.execute('SELECT * FROM youtube_videos ORDER BY published_date DESC, scraped_at DESC')
            video_rows = cursor.fetchall()
            video_list = [dict(row) for row in video_rows]
            
            return {
                "news": news_list,
                "youtube": video_list,
                "updated_at": datetime.now().isoformat()
            }
