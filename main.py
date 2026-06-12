import os
import json
from database import Database
from analyzer import ContentAnalyzer
from monitors.news_monitor import NewsMonitor
from monitors.youtube_monitor import YouTubeMonitor

def main():
    print("==================================================")
    print("INICIANDO BOT DE MONITOREO - MUNICIPALIDAD DE JESÚS MARÍA")
    print("==================================================")
    
    # Asegurar que el directorio de datos existe
    # (En nuestro caso estamos ejecutando en la raíz del proyecto)
    
    # 1. Inicializar base de datos y analizador
    db = Database("monitor.db")
    analyzer = ContentAnalyzer("config.json")
    
    # 2. Inicializar y ejecutar el monitoreo de noticias
    news_monitor = NewsMonitor(analyzer, db)
    new_articles = news_monitor.monitor()
    print(f"\n[Noticias] Se agregaron {len(new_articles)} nuevas noticias.")
    
    # 3. Inicializar y ejecutar el monitoreo de YouTube
    youtube_monitor = YouTubeMonitor(analyzer, db)
    new_videos = youtube_monitor.monitor()
    print(f"\n[YouTube] Se agregaron {len(new_videos)} nuevos videos.")
    
    # 4. Generar y exportar datos compilados para el Dashboard Web
    print("\n[Exportación] Actualizando datos para el panel web...")
    all_data = db.get_all_data()
    
    dashboard_dir = "dashboard"
    os.makedirs(dashboard_dir, exist_ok=True)
    
    data_json_path = os.path.join(dashboard_dir, "data.json")
    data_js_path = os.path.join(dashboard_dir, "data.js")
    
    # Guardar como JSON legible
    with open(data_json_path, 'w', encoding='utf-8') as f:
        json.dump(all_data, f, ensure_ascii=False, indent=2)
        
    # Guardar como JS para evitar bloqueos CORS en archivos locales
    with open(data_js_path, 'w', encoding='utf-8') as f:
        f.write(f"window.monitorData = {json.dumps(all_data, ensure_ascii=False, indent=2)};")
        
    print(f"[Exportación] Archivos guardados correctamente en: {dashboard_dir}")
    print("==================================================")
    print("MONITOREO FINALIZADO CON ÉXITO")
    print("==================================================")

if __name__ == "__main__":
    main()
