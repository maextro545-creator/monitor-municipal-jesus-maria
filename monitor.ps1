# MuniWatch - Script de Monitoreo en PowerShell (Sin dependencias externas)
# Rastreará noticias de Google News RSS y videos de YouTube.

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "INICIANDO BOT DE MONITOREO - MUNICIPALIDAD DE JESÚS MARÍA" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# 1. Cargar Configuración
$ConfigPath = Join-Path $ScriptDir "config.json"
if (-not (Test-Path $ConfigPath)) {
    Write-Error "No se encontró config.json en $ConfigPath"
}
$Config = Get-Content -Raw -Path $ConfigPath -Encoding utf8 | ConvertFrom-Json
Write-Host "[Info] Configuración cargada correctamente." -ForegroundColor Green

# ==============================================================================
# DEFINICIÓN DE FUNCIONES (Definidas al inicio para evitar problemas de orden)
# ==============================================================================

# 3. Función auxiliar para quitar acentos y normalizar caracteres Unicode
function Remove-Accents {
    param ([string]$string)
    if ([string]::IsNullOrEmpty($string)) { return "" }
    $normalized = $string.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($char in $normalized.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($char) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($char)
        }
    }
    return $sb.ToString().Normalize([System.Text.NormalizationForm]::FormC)
}

# Función para resolver el redirect interno de Google News a la URL real del medio
function Resolve-GoogleNewsUrl {
    param ([string]$url)
    if ($url -notlike "*news.google.com/rss/articles/*") {
        return $url
    }
    $userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    try {
        # Fetch wrapper page
        $resp = Invoke-WebRequest -Uri $url -UserAgent $userAgent -TimeoutSec 5 -UseBasicParsing
        
        if ($resp.Content -match 'data-p="([^"]+)"') {
            $dataP = [System.Net.WebUtility]::HtmlDecode($Matches[1])
            $jsonStr = $dataP.Replace('%.@.', '["garturlreq",')
            
            # Parse as JSON
            $obj = ConvertFrom-Json $jsonStr
            
            $count = $obj.Length
            # Slice: obj[:-6] + obj[-2:]
            $slice1 = $obj[0..($count - 7)]
            $slice2 = $obj[($count - 2)..($count - 1)]
            
            $slicedObj = @()
            foreach ($item in $slice1) { $slicedObj += ,$item }
            foreach ($item in $slice2) { $slicedObj += ,$item }
            
            $slicedJson = ConvertTo-Json -InputObject $slicedObj -Depth 10 -Compress
            
            # Prepare batch request payload
            $inner = @("Fbv4je", $slicedJson, $null, "generic")
            $nested = , (, $inner)
            $fReq = ConvertTo-Json -InputObject $nested -Depth 10 -Compress
            
            $body = "f.req=" + [System.Net.WebUtility]::UrlEncode($fReq)
            
            # Send POST request
            $postUrl = "https://news.google.com/_/DotsSplashUi/data/batchexecute"
            $headers = @{
                "Content-Type" = "application/x-www-form-urlencoded;charset=UTF-8"
            }
            
            $postResp = Invoke-WebRequest -Uri $postUrl -Method Post -Body $body -Headers $headers -UserAgent $userAgent -TimeoutSec 5 -UseBasicParsing
            $respText = $postResp.Content
            
            $cleanResp = $respText.TrimStart(")]}'`r`n ")
            $cleanResp = $cleanResp.Trim()
            
            $outer = ConvertFrom-Json $cleanResp
            $innerStr = $outer[0][2]
            $inner = ConvertFrom-Json $innerStr
            if ($inner[1] -like "http*") {
                return $inner[1]
            }
        }
    } catch {
        # Fallback to returning original URL if resolution fails
    }
    return $url
}

# Función para obtener datos de Facebook usando Apify
function Get-FacebookDataFromApify {
    param (
        [string]$url
    )
    if ([string]::IsNullOrEmpty($Config.apify_token)) {
        return $null
    }
    
    Write-Host "    [Apify] Rastreando publicación de Facebook: $url ..." -ForegroundColor Cyan
    try {
        $body = @{
            startUrls = @( @{ url = $url } )
            resultsLimit = 1
        } | ConvertTo-Json -Depth 5
        $apifyUrl = "https://api.apify.com/v2/acts/apify~facebook-posts-scraper/run-sync-get-dataset-items?token=$($Config.apify_token)"
        
        # Timeout de 120 segundos para la consulta sincrónica
        $resp = Invoke-RestMethod -Uri $apifyUrl -Method Post -Body $body -ContentType "application/json" -TimeoutSec 120
        if ($resp -and $resp.Count -gt 0) {
            $item = $resp[0]
            
            $imgUrl = ""
            if ($item.media -and $item.media.photo_image -and $item.media.photo_image.uri) {
                $imgUrl = $item.media.photo_image.uri
            } elseif ($item.media -and $item.media.Count -gt 0) {
                $m = $item.media[0]
                if ($m.photo_image -and $m.photo_image.uri) { $imgUrl = $m.photo_image.uri }
                elseif ($m.uri) { $imgUrl = $m.uri }
                elseif ($m.url) { $imgUrl = $m.url }
            } elseif ($item.image) {
                $imgUrl = $item.image
            } elseif ($item.image_url) {
                $imgUrl = $item.image_url
            } elseif ($item.attachments -and $item.attachments.Count -gt 0) {
                $att = $item.attachments[0]
                if ($att.media -and $att.media.image -and $att.media.image.src) {
                    $imgUrl = $att.media.image.src
                }
            }
            
            $postText = $item.postText
            if ([string]::IsNullOrEmpty($postText)) {
                $postText = $item.text
            }
            
            return [PSCustomObject]@{
                image_url = Optimize-FacebookImageUrl $imgUrl
                text = $postText
                author = $item.pageName
            }
        }
    } catch {
        Write-Host "    [Warning] Error en Apify al obtener datos de Facebook: $_" -ForegroundColor DarkYellow
    }
    return $null
}

# Función para buscar en Facebook usando Apify con cookies
function Search-FacebookWithApify {
    param (
        [string]$query
    )
    if ([string]::IsNullOrEmpty($Config.apify_token) -or $null -eq $Config.facebook_cookies -or $Config.facebook_cookies.Count -eq 0) {
        return @()
    }
    
    # Calcular fecha de inicio (hace 5 días)
    $startDate = (Get-Date).AddDays(-5).ToString("yyyy-MM-dd")
    Write-Host "    [Apify] Buscando en Facebook para: '$query' desde $startDate..." -ForegroundColor Cyan
    
    $body = @{
        query = $query
        maxResults = 20
        recent_posts = $true
        start_date = $startDate
        cookies = $Config.facebook_cookies
    } | ConvertTo-Json -Depth 10
    
    $apifyUrl = "https://api.apify.com/v2/acts/scraper_one~facebook-posts-search/run-sync-get-dataset-items?token=$($Config.apify_token)"
    
    try {
        # Timeout de 120 segundos para la consulta sincrónica
        $resp = Invoke-RestMethod -Uri $apifyUrl -Method Post -Body $body -ContentType "application/json" -TimeoutSec 120
        if ($resp -and $resp.Count -gt 0) {
            return $resp
        }
    } catch {
        Write-Host "    [Warning] Error en Apify al buscar en Facebook para '$query': $_" -ForegroundColor DarkYellow
    }
    return @()
}

# Función para optimizar la resolución de imágenes de Facebook si son avatares/perfiles
function Optimize-FacebookImageUrl {
    param (
        [string]$url
    )
    if ([string]::IsNullOrEmpty($url)) {
        return $url
    }
    if ($url -like "*facebook.com*" -or $url -like "*fbcdn.net*") {
        $url = $url -replace 'ctp=[sp]\d+x\d+', 'ctp=s320x320'
    }
    return $url
}

# Función para extraer imagen og:image (OpenGraph) de un sitio web de forma agresiva
function Get-OGImage {
    param (
        [string]$url,
        [string]$htmlContent = $null
    )
    # Si es un enlace de Facebook y tenemos token de Apify, usamos Apify para obtener la imagen
    if ($url -like "*facebook.com*" -and -not [string]::IsNullOrEmpty($Config.apify_token)) {
        $fbData = Get-FacebookDataFromApify $url
        if ($fbData -and -not [string]::IsNullOrEmpty($fbData.image_url)) {
            return $fbData.image_url
        }
    }

    $userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    try {
        $html = $htmlContent
        if ([string]::IsNullOrEmpty($html)) {
            $resp = Invoke-WebRequest -Uri $url -TimeoutSec 5 -UseBasicParsing -UserAgent $userAgent
            $html = $resp.Content
        }
        
        # Helper inline function to make url absolute
        $makeAbsolute = {
            param ([string]$imgUrl, [string]$pageUrl)
            $imgUrl = [System.Net.WebUtility]::HtmlDecode($imgUrl)
            if ($imgUrl -like "/*") {
                $uri = New-Object System.Uri($pageUrl)
                return $uri.Scheme + "://" + $uri.Host + $imgUrl
            } elseif ($imgUrl -notlike "http*") {
                $uri = New-Object System.Uri($pageUrl)
                return $uri.Scheme + "://" + $uri.Host + "/" + $imgUrl
            }
            return $imgUrl
        }
        
        # 1. Buscar metadatos estándar de imágenes (OpenGraph, Twitter Cards, itemprop, link)
        if ($html -match '(?i)<meta\s+[^>]*property=["'']og:image["'']\s+[^>]*content=["'']([^"'']+)["'']') {
            $img = &$makeAbsolute $Matches[1] $url
            if ($img -notlike "*googleusercontent.com*" -and $img -notlike "*google.com*") { return $img }
        }
        if ($html -match '(?i)<meta\s+[^>]*content=["'']([^"'']+)["'']\s+[^>]*property=["'']og:image["'']') {
            $img = &$makeAbsolute $Matches[1] $url
            if ($img -notlike "*googleusercontent.com*" -and $img -notlike "*google.com*") { return $img }
        }
        if ($html -match '(?i)<meta\s+[^>]*name=["'']twitter:image["'']\s+[^>]*content=["'']([^"'']+)["'']') {
            $img = &$makeAbsolute $Matches[1] $url
            if ($img -notlike "*googleusercontent.com*" -and $img -notlike "*google.com*") { return $img }
        }
        if ($html -match '(?i)<meta\s+[^>]*content=["'']([^"'']+)["'']\s+[^>]*name=["'']twitter:image["'']') {
            $img = &$makeAbsolute $Matches[1] $url
            if ($img -notlike "*googleusercontent.com*" -and $img -notlike "*google.com*") { return $img }
        }
        if ($html -match '(?i)<link\s+[^>]*rel=["'']image_src["'']\s+[^>]*href=["'']([^"'']+)["'']') {
            $img = &$makeAbsolute $Matches[1] $url
            if ($img -notlike "*googleusercontent.com*" -and $img -notlike "*google.com*") { return $img }
        }
        if ($html -match '(?i)<link\s+[^>]*href=["'']([^"'']+)["'']\s+[^>]*rel=["'']image_src["'']') {
            $img = &$makeAbsolute $Matches[1] $url
            if ($img -notlike "*googleusercontent.com*" -and $img -notlike "*google.com*") { return $img }
        }
        
        # 2. Scraping agresivo de etiquetas img (buscar la primera imagen grande y relevante del artículo)
        $imgMatches = [regex]::Matches($html, '(?i)<img\s+[^>]*src=["'']([^"'']+)["'']')
        foreach ($m in $imgMatches) {
            $imgUrl = &$makeAbsolute $m.Groups[1].Value $url
            # Evitar capturar tracking pixels, avatares, logos o iconos de redes sociales, y logos de Google
            if ($imgUrl -like "http*" -and 
                $imgUrl -notlike "*logo*" -and 
                $imgUrl -notlike "*icon*" -and 
                $imgUrl -notlike "*pixel*" -and 
                $imgUrl -notlike "*avatar*" -and 
                $imgUrl -notlike "*ad.*" -and 
                $imgUrl -notlike "*banner*" -and 
                $imgUrl -notlike "*sprite*" -and 
                $imgUrl -notlike "*loader*" -and 
                $imgUrl -notlike "*.gif" -and 
                $imgUrl -notlike "*spacer*" -and
                $imgUrl -notlike "*googleusercontent.com*" -and 
                $imgUrl -notlike "*google.com*") {
                return $imgUrl
            }
        }
    } catch {
        # Ignorar errores de descarga de portada y permitir fallback de stock
    }
    return ""
}

# 4. Función de Análisis de Sentimiento
function Analyze-Sentiment {
    param (
        [string]$Text
    )
    if ([string]::IsNullOrEmpty($Text)) {
        return @{ sentiment = "neutral"; score = 0.0 }
    }
    
    # Quitar acentos y minúsculas para análisis uniforme
    $cleanText = Remove-Accents ($Text.ToLower())
    $cleanText = $cleanText -replace '[^\w\s]', ' '
    
    # Tokenizar en palabras
    $words = $cleanText -split '\s+' | Where-Object { $_ -ne "" }
    
    $posWords = $Config.sentiment_positive_words | ForEach-Object { Remove-Accents ($_.ToLower()) }
    $negWords = $Config.sentiment_negative_words | ForEach-Object { Remove-Accents ($_.ToLower()) }
    
    $posCount = 0
    $negCount = 0
    
    foreach ($word in $words) {
        # Evaluar palabras positivas
        foreach ($pos in $posWords) {
            if ($word -like "*$pos*") {
                $posCount++
                break
            }
        }
        # Evaluar palabras negativas
        foreach ($neg in $negWords) {
            if ($word -like "*$neg*") {
                $negCount++
                break
            }
        }
    }
    
    $total = $posCount + $negCount
    $score = 0.0
    $sentiment = "neutral"
    
    if ($total -gt 0) {
        $score = [Math]::Round(($posCount - $negCount) / $total, 2)
        if ($score -gt 0.15) {
            $sentiment = "positivo"
        } elseif ($score -lt -0.15) {
            $sentiment = "negativo"
        }
    }
    
    return @{ sentiment = $sentiment; score = $score }
}

# 5. Función de Verificación de Relevancia
function Check-Relevance {
    param (
        [string]$Text
    )
    $cleanText = Remove-Accents ($Text.ToLower())
    
    # Filtrar explícitamente noticias de Argentina / Córdoba / Festival de Doma
    $excludeKeywords = @("cordoba", "argentina", "folklore", "doma", "jineteada", "chaqueño", "milei", "festival", "anfiteatro", "festivaleras")
    foreach ($ex in $excludeKeywords) {
        if ($cleanText.Contains($ex)) {
            return 0
        }
    }
    
    $keywords = @("jesus maria", "jesus galvez", "alcalde galvez", "municipalidad de jesus maria")
    foreach ($kw in $keywords) {
        if ($cleanText.Contains($kw)) {
            return 1
        }
    }
    return 0
}

# ==============================================================================


# 2. Inicializar o Cargar Base de Datos Local (JSON)
$DbPath = Join-Path $ScriptDir "database.json"
if (Test-Path $DbPath) {
    $Db = Get-Content -Raw -Path $DbPath -Encoding utf8 | ConvertFrom-Json
    # Asegurarse de que exista la propiedad twitter
    if ($null -eq $Db.twitter) {
        $Db | Add-Member -MemberType NoteProperty -Name "twitter" -Value @()
    }
    
    # Limpieza de base de datos para excluir noticias ajenas a Perú (Argentina/Córdoba)
    $excludeKeywords = @("cordoba", "argentina", "folklore", "doma", "jineteada", "chaqueño", "milei", "festival", "anfiteatro", "festivaleras")
    if ($Db.news) {
        $Db.news = @($Db.news | Where-Object {
            $combined = Remove-Accents ("$($_.title) $($_.summary)".ToLower())
            $exclude = $false
            foreach ($ex in $excludeKeywords) {
                if ($combined.Contains($ex)) { $exclude = $true; break }
            }
            -not $exclude
        })
    }
    if ($Db.twitter) {
        $Db.twitter = @($Db.twitter | Where-Object {
            $combined = Remove-Accents ("$($_.title)".ToLower())
            $exclude = $false
            foreach ($ex in $excludeKeywords) {
                if ($combined.Contains($ex)) { $exclude = $true; break }
            }
            -not $exclude
        })
    }
} else {
    $Db = [PSCustomObject]@{
        news = @()
        youtube = @()
        twitter = @()
    }
}

# --- Migración Retroactiva para obtener imágenes reales en noticias antiguas ---
Write-Host "[Migración] Verificando si hay noticias con logos de Google o imágenes de stock..." -ForegroundColor Yellow
$UpdatedMigrationCount = 0
foreach ($article in $Db.news) {
    $hasGoogleImg = $article.image_url -like "*googleusercontent.com*" -or $article.image_url -like "*google.com*"
    $hasUnsplashImg = $article.image_url -like "*images.unsplash.com*"
    $isEmptyImg = [string]::IsNullOrEmpty($article.image_url)
    
    if ($hasGoogleImg -or $hasUnsplashImg -or $isEmptyImg) {
        Write-Host "  [~] Intentando mejorar imagen para: $($article.title)" -ForegroundColor Gray
        
        # Resolver la URL real
        $realUrl = Resolve-GoogleNewsUrl $article.url
        
        # Scrapear imagen real
        $newImg = Get-OGImage $realUrl
        if (-not [string]::IsNullOrEmpty($newImg) -and $newImg -notlike "*googleusercontent.com*" -and $newImg -notlike "*google.com*") {
            $article.image_url = $newImg
            $article.url = $realUrl
            $UpdatedMigrationCount++
            Write-Host "    [+] ¡Éxito! Nueva imagen: $newImg" -ForegroundColor Green
        } else {
            # Si era del logo de Google, la reemplazamos con fallback para no mostrar el logo "GE"
            if ($hasGoogleImg) {
                $fallbackImages = @(
                    "https://images.unsplash.com/photo-1495020689067-958852a6565d?auto=format&fit=crop&w=600&q=80",
                    "https://images.unsplash.com/photo-1504711434969-e33886168f5c?auto=format&fit=crop&w=600&q=80",
                    "https://images.unsplash.com/photo-1450133064473-71024230f91b?auto=format&fit=crop&w=600&q=80",
                    "https://images.unsplash.com/photo-1557804506-669a67965ba0?auto=format&fit=crop&w=600&q=80"
                )
                $fallbackIndex = $article.title.Length % $fallbackImages.Count
                $article.image_url = $fallbackImages[$fallbackIndex]
                $article.url = $realUrl
                $UpdatedMigrationCount++
                Write-Host "    [+] Reemplazado logo de Google por Unsplash stock" -ForegroundColor DarkGray
            }
        }
    }
}
if ($UpdatedMigrationCount -gt 0) {
    Write-Host "[Migración] Se actualizaron $UpdatedMigrationCount noticias antiguas con imágenes correctas." -ForegroundColor Green
    $Db | ConvertTo-Json -Depth 10 | Out-File -FilePath $DbPath -Encoding utf8
}

# --- Migración Retroactiva para obtener imágenes reales en tweets antiguos ---
Write-Host "[Migración] Verificando si hay tweets con imágenes de stock de Unsplash..." -ForegroundColor Yellow
$UpdatedTwitterMigrationCount = 0
if ($Db.twitter) {
    foreach ($tweet in $Db.twitter) {
        $hasUnsplashImg = $tweet.image_url -like "*images.unsplash.com*"
        $isEmptyImg = [string]::IsNullOrEmpty($tweet.image_url)
        
        if ($hasUnsplashImg -or $isEmptyImg) {
            Write-Host "  [~] Intentando obtener imagen real para tweet: @$($tweet.author) : $($tweet.title)" -ForegroundColor Gray
            
            # Limpiar URL de Twitter (eliminar /photo/4, etc.)
            $cleanTweetUrl = $tweet.url -replace '(?i)(/status/\d+)/.*$', '$1'
            
            # Scrapear imagen real
            $newImg = Get-OGImage $cleanTweetUrl
            if (-not [string]::IsNullOrEmpty($newImg)) {
                $tweet.image_url = $newImg
                $tweet.url = $cleanTweetUrl
                $UpdatedTwitterMigrationCount++
                Write-Host "    [+] ¡Éxito! Nueva imagen de tweet: $newImg" -ForegroundColor Green
            }
        }
    }
}
if ($UpdatedTwitterMigrationCount -gt 0) {
    Write-Host "[Migración] Se actualizaron $UpdatedTwitterMigrationCount tweets antiguos con imágenes correctas." -ForegroundColor Green
    $Db | ConvertTo-Json -Depth 10 | Out-File -FilePath $DbPath -Encoding utf8
}


# 5. Monitorear Noticias (Google News RSS)
Write-Host "`n[Noticias] Iniciando rastreo en Google News..." -ForegroundColor Yellow
$NewNewsCount = 0
$NewFacebookCount = 0
$UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

foreach ($query in $Config.queries) {
    Write-Host "  [-] Consultando para: '$query'..." -ForegroundColor Gray
    # Limitar la búsqueda de noticias a los últimos 5 días
    $queryWithTime = "$query when:5d"
    $encodedQuery = [uri]::EscapeDataString($queryWithTime)
    $rssUrl = "https://news.google.com/rss/search?q=$encodedQuery&hl=es-419&gl=PE&ceid=PE:es"
    
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", $UserAgent)
        $bytes = $webClient.DownloadData($rssUrl)
        $xmlText = [System.Text.Encoding]::UTF8.GetString($bytes)
        [xml]$feed = $xmlText
        $items = $feed.rss.channel.item
        if ($null -eq $items) { continue }
        
        # Tomar los primeros resultados configurados
        $limit = [Math]::Min($items.Count, $Config.news_max_results)
        
        for ($i = 0; $i -lt $limit; $i++) {
            $item = $items[$i]
            $url = $item.link
            
            # Resolver la URL real primero
            Write-Host "    [~] Resolviendo enlace de Google News..." -ForegroundColor Gray
            $realUrl = Resolve-GoogleNewsUrl $url
            
            # Verificar si ya existe en la DB (comparando con la URL de Google News y la resuelta)
            $exists = $false
            foreach ($existing in $Db.news) {
                if ($existing.url -eq $url -or $existing.url -eq $realUrl) {
                    $exists = $true
                    break
                }
            }
            if ($exists) { continue }
            
            $title = $item.title
            $source = $item.source.InnerText
            $pubDateRaw = $item.pubDate
            
            # Formatear la fecha usando InvariantCulture y filtrar por año actual
            $pubDate = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            $currentYear = (Get-Date).Year
            $skipArticle = $false
            try {
                $parsedDate = [DateTime]::Parse($pubDateRaw, [System.Globalization.CultureInfo]::InvariantCulture)
                $pubDate = $parsedDate.ToString("yyyy-MM-ddTHH:mm:ss")
                if ($parsedDate.Year -ne $currentYear) {
                    $skipArticle = $true
                }
            } catch {}
            
            if ($skipArticle) {
                continue
            }
            
            # Limpiar descripción HTML
            $summary = $item.description
            if ($summary) {
                $summary = $summary -replace '<[^>]+>', ''
            } else {
                $summary = ""
            }
            
            # Si es de Facebook y tenemos token de Apify, intentamos enriquecer la noticia
            $fbData = $null
            if ($realUrl -like "*facebook.com*" -and -not [string]::IsNullOrEmpty($Config.apify_token)) {
                $fbData = Get-FacebookDataFromApify $realUrl
                if ($fbData) {
                    if ($fbData.text) {
                        $summary = $fbData.text
                    }
                    if ($fbData.author) {
                        $source = $fbData.author
                    }
                }
            }
            
            # Analizar relevancia y sentimiento
            $combinedText = "$title $summary"
            $relevance = Check-Relevance $combinedText
            if ($relevance -eq 0) { continue }
            
            $analysis = Analyze-Sentiment $combinedText
            
            # Obtener imagen previa (og:image) o asignar una de stock premium si está vacía
            $imageUrl = ""
            if ($fbData -and $fbData.image_url) {
                $imageUrl = $fbData.image_url
            } else {
                Write-Host "    [~] Portada: Obteniendo imagen de vista previa desde $realUrl ..." -ForegroundColor Gray
                $imageUrl = Get-OGImage $realUrl
            }
            
            # Asegurar resolución alta para imágenes de Facebook
            $imageUrl = Optimize-FacebookImageUrl $imageUrl
            
            if ([string]::IsNullOrEmpty($imageUrl)) {
                $fallbackImages = @(
                    "https://images.unsplash.com/photo-1495020689067-958852a6565d?auto=format&fit=crop&w=600&q=80", # Prensa
                    "https://images.unsplash.com/photo-1504711434969-e33886168f5c?auto=format&fit=crop&w=600&q=80", # Periódicos
                    "https://images.unsplash.com/photo-1450133064473-71024230f91b?auto=format&fit=crop&w=600&q=80", # Micrófono
                    "https://images.unsplash.com/photo-1557804506-669a67965ba0?auto=format&fit=crop&w=600&q=80"  # Oficina
                )
                $fallbackIndex = $title.Length % $fallbackImages.Count
                $imageUrl = $fallbackImages[$fallbackIndex]
            }
            
            $newArticle = [PSCustomObject]@{
                url = $realUrl
                query = $query
                title = $title
                source = $source
                published_date = $pubDate
                summary = $summary
                sentiment = $analysis.sentiment
                sentiment_score = $analysis.score
                relevance = $relevance
                image_url = $imageUrl
                scraped_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            }
            
            $Db.news += $newArticle
            $NewNewsCount++
            Write-Host "    [+] Nueva noticia: $title ($($analysis.sentiment))" -ForegroundColor Green
        }
    } catch {
        Write-Host "    [Warning] Error al consultar noticias para '$query': $_" -ForegroundColor DarkYellow
    }
}

# 6. Monitorear YouTube
Write-Host "`n[YouTube] Iniciando rastreo en YouTube..." -ForegroundColor Yellow
$NewYoutubeCount = 0

foreach ($query in $Config.queries) {
    Write-Host "  [-] Consultando para: '$query'..." -ForegroundColor Gray
    $encodedQuery = [uri]::EscapeDataString($query)
    # Ordenado por fecha (sp=CAI%253D)
    $ytUrl = "https://www.youtube.com/results?search_query=$encodedQuery&sp=CAI%253D"
    
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", $UserAgent)
        $bytes = $webClient.DownloadData($ytUrl)
        $html = [System.Text.Encoding]::UTF8.GetString($bytes)
        
        # Extraer videoIds con Regex
        $matches = [regex]::Matches($html, '/watch\?v=([a-zA-Z0-9_-]{11})')
        $videoIds = @()
        foreach ($m in $matches) {
            $vId = $m.Groups[1].Value
            if ($vId -notin $videoIds) {
                $videoIds += $vId
            }
        }
        
        $limit = [Math]::Min($videoIds.Count, $Config.youtube_max_results)
        $selectedIds = $videoIds | Select-Object -First $limit
        
        foreach ($vId in $selectedIds) {
            # Verificar si ya existe en la DB
            $exists = $false
            foreach ($existing in $Db.youtube) {
                if ($existing.video_id -eq $vId) {
                    $exists = $true
                    break
                }
            }
            if ($exists) { continue }
            
            # Obtener metadatos con oEmbed (Título y Canal)
            $oembedUrl = "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$vId&format=json"
            $title = "Video YouTube $vId"
            $channel = "YouTube"
            
            try {
                $oembed = Invoke-RestMethod -Uri $oembedUrl -TimeoutSec 5
                $title = $oembed.title
                $channel = $oembed.author_name
            } catch {
                # Fallback si falla oembed
            }
            
            # Analizar relevancia y sentimiento
            $relevance = Check-Relevance "$title"
            if ($relevance -eq 0) {
                # Para YouTube, si el título no es relevante, no lo agregamos
                continue
            }
            
            # Obtener fecha de carga real del video para filtrar por año actual
            $watchUrl = "https://www.youtube.com/watch?v=$vId"
            $videoDate = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            $skipVideo = $false
            $currentYear = (Get-Date).Year
            try {
                $webClient = New-Object System.Net.WebClient
                $webClient.Headers.Add("User-Agent", $UserAgent)
                $videoBytes = $webClient.DownloadData($watchUrl)
                $videoHtml = [System.Text.Encoding]::UTF8.GetString($videoBytes)
                
                if ($videoHtml -match 'itemprop="uploadDate"\s+content="([^"]+)"') {
                    $rawDate = $Matches[1]
                    $parsedVideoDate = [DateTime]::Parse($rawDate)
                    $videoDate = $parsedVideoDate.ToString("yyyy-MM-ddTHH:mm:ss")
                    if ($parsedVideoDate.Year -ne $currentYear) {
                        $skipVideo = $true
                    }
                }
            } catch {
                # En caso de error, dejamos pasar
            }

            if ($skipVideo) {
                continue
            }
            
            $analysis = Analyze-Sentiment "$title"
            
            $newVideo = [PSCustomObject]@{
                video_id = $vId
                query = $query
                title = $title
                channel = $channel
                published_date = $videoDate
                description = "Video monitoreado de YouTube."
                transcript_snippet = "Menciones detectadas en el video: $title"
                sentiment = $analysis.sentiment
                sentiment_score = $analysis.score
                relevance = $relevance
                image_url = "https://img.youtube.com/vi/$vId/hqdefault.jpg"
                scraped_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            }
            
            $Db.youtube += $newVideo
            $NewYoutubeCount++
            Write-Host "    [+] Nuevo video: $title ($($analysis.sentiment))" -ForegroundColor Green
        }
    } catch {
        Write-Host "    [Warning] Error al consultar YouTube para '$query': $_" -ForegroundColor DarkYellow
    }
}

# 6.b Monitorear Twitter/X
Write-Host "`n[Twitter] Iniciando rastreo en Twitter/X..." -ForegroundColor Yellow
$NewTwitterCount = 0

foreach ($query in $Config.queries) {
    Write-Host "  [-] Consultando para: '$query'..." -ForegroundColor Gray
    # Consulta combinada en Google News RSS para x.com y twitter.com, limitada a los últimos 5 días
    $combinedQuery = "(site:x.com OR site:twitter.com) `"$query`" when:5d"
    $encodedQuery = [uri]::EscapeDataString($combinedQuery)
    $rssUrl = "https://news.google.com/rss/search?q=$encodedQuery&hl=es-419&gl=PE&ceid=PE:es"
    
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", $UserAgent)
        $bytes = $webClient.DownloadData($rssUrl)
        $xmlText = [System.Text.Encoding]::UTF8.GetString($bytes)
        [xml]$feed = $xmlText
        $items = $feed.rss.channel.item
        if ($null -eq $items) { continue }
        
        $limit = [Math]::Min($items.Count, 10) # Limitar a 10 tweets por consulta
        $subset = @()
        if ($items -is [array]) { $subset = $items } else { $subset = @($items) }
        $selectedItems = $subset | Select-Object -First $limit
        
        foreach ($item in $selectedItems) {
            $url = $item.link
            
            # Resolver la URL real primero
            Write-Host "    [~] Resolviendo enlace de Twitter..." -ForegroundColor Gray
            $realUrl = Resolve-GoogleNewsUrl $url
            # Limpiar URL de Twitter (ej. eliminar /photo/4 o cualquier subpath posterior a /status/ID)
            $realUrl = $realUrl -replace '(?i)(/status/\d+)/.*$', '$1'
            
            # Verificar si ya existe en la DB (comparando con la URL original y la resuelta)
            $exists = $false
            foreach ($existing in $Db.twitter) {
                if ($existing.url -eq $url -or $existing.url -eq $realUrl) {
                    $exists = $true
                    break
                }
            }
            if ($exists) { continue }
            
            # Extraer autor (nombre de usuario) de la URL de Twitter/X
            # Ejemplo: https://x.com/ElmerAyala_PE/status/123456
            $author = "TwitterUser"
            if ($realUrl -match '(?i)https?://(?:www\.)?(?:x|twitter)\.com/([^/]+)/status') {
                $author = $Matches[1]
            }
            
            $title = $item.title
            # Limpiar el sufijo " - x.com" o " - Twitter" del título si existe
            $title = $title -replace '(?i)\s*-\s*(x\.com|twitter)\s*$', ''
            
            $pubDateRaw = $item.pubDate
            $pubDate = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            $currentYear = (Get-Date).Year
            $skipTweet = $false
            try {
                $parsedDate = [DateTime]::Parse($pubDateRaw, [System.Globalization.CultureInfo]::InvariantCulture)
                $pubDate = $parsedDate.ToString("yyyy-MM-ddTHH:mm:ss")
                if ($parsedDate.Year -ne $currentYear) {
                    $skipTweet = $true
                }
            } catch {}
            
            if ($skipTweet) { continue }
            
            # Analizar relevancia y sentimiento
            $relevance = Check-Relevance $title
            if ($relevance -eq 0) { continue }
            
            $analysis = Analyze-Sentiment $title
            
            # Imagen real de Twitter usando Get-OGImage
            Write-Host "    [~] Portada: Obteniendo imagen de Twitter..." -ForegroundColor Gray
            $imageUrl = Get-OGImage $realUrl
            if ([string]::IsNullOrEmpty($imageUrl)) {
                $imageUrl = "https://images.unsplash.com/photo-1611605698335-8b15d27e03f3?auto=format&fit=crop&w=600&q=80"
            }
            
            $newTweet = [PSCustomObject]@{
                url = $realUrl
                query = $query
                title = $title
                author = $author
                published_date = $pubDate
                sentiment = $analysis.sentiment
                sentiment_score = $analysis.score
                relevance = $relevance
                image_url = $imageUrl
                scraped_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            }
            
            $Db.twitter += $newTweet
            $NewTwitterCount++
            Write-Host "    [+] Nuevo tweet: @$author : $title ($($analysis.sentiment))" -ForegroundColor Green
        }
    } catch {
        Write-Host "    [Warning] Error al consultar Twitter para '$query': $_" -ForegroundColor DarkYellow
    }
}

# 6.c Monitorear Facebook vía Búsqueda de Apify (Solo si se configuran cookies)
if ($null -ne $Config.facebook_cookies -and $Config.facebook_cookies.Count -gt 0 -and -not [string]::IsNullOrEmpty($Config.apify_token)) {
    Write-Host "`n[Facebook] Iniciando búsqueda de palabras clave en Facebook con Apify..." -ForegroundColor Yellow
    $NewFacebookCount = 0
    foreach ($query in $Config.queries) {
        $items = Search-FacebookWithApify $query
        if ($null -eq $items -or $items.Count -eq 0) { continue }
        
        foreach ($item in $items) {
            $url = $item.url
            if ([string]::IsNullOrEmpty($url)) { $url = $item.permalink }
            if ([string]::IsNullOrEmpty($url)) { continue }
            
            # Limpiar URL para evitar duplicados con parámetros de tracking
            $realUrl = $url -replace '\?.*$', ''
            
            # Verificar si ya existe en la DB
            $exists = $false
            foreach ($existing in $Db.news) {
                if ($existing.url -eq $realUrl) {
                    $exists = $true
                    break
                }
            }
            if ($exists) { continue }
            
            # Extraer título y resumen
            $postText = $item.postText
            if ([string]::IsNullOrEmpty($postText)) { $postText = $item.message }
            if ([string]::IsNullOrEmpty($postText)) { $postText = $item.text }
            if ([string]::IsNullOrEmpty($postText)) { continue }
            
            $title = $postText
            if ($title.Length -gt 100) {
                $title = $title.Substring(0, 97) + "..."
            }
            # Reemplazar saltos de línea en el título
            $title = $title -replace "`r?`n", " "
            
            $source = $item.pageName
            if ([string]::IsNullOrEmpty($source)) { $source = $item.author.name }
            if ([string]::IsNullOrEmpty($source)) { $source = "Facebook Page" }
            
            # Relevancia y sentimiento
            $relevance = Check-Relevance $postText
            if ($relevance -eq 0) { continue }
            
            $analysis = Analyze-Sentiment $postText
            
            # Extraer imagen
            $imageUrl = ""
            if ($item.media -and $item.media.photo_image -and $item.media.photo_image.uri) {
                $imageUrl = $item.media.photo_image.uri
            } elseif ($item.media -and $item.media.Count -gt 0) {
                $m = $item.media[0]
                if ($m.photo_image -and $m.photo_image.uri) { $imageUrl = $m.photo_image.uri }
                elseif ($m.uri) { $imageUrl = $m.uri }
                elseif ($m.url) { $imageUrl = $m.url }
            } elseif ($item.image) {
                $imageUrl = $item.image
            } elseif ($item.image_url) {
                $imageUrl = $item.image_url
            } elseif ($item.video_thumbnail) {
                $imageUrl = $item.video_thumbnail
            } elseif ($item.attachments -and $item.attachments.Count -gt 0) {
                $att = $item.attachments[0]
                if ($att.media -and $att.media.image -and $att.media.image.src) {
                    $imageUrl = $att.media.image.src
                }
            }
            
            if ([string]::IsNullOrEmpty($imageUrl)) {
                # Fallback al avatar del autor antes del fallback genérico
                if ($item.author -and $item.author.profile_picture_url) {
                    $imageUrl = $item.author.profile_picture_url
                } elseif ($item.author -and $item.author.profilePicture) {
                    $imageUrl = $item.author.profilePicture
                } else {
                    $imageUrl = "https://images.unsplash.com/photo-1544716278-ca5e3f4abd8c?auto=format&fit=crop&w=600&q=80"
                }
            }
            
            # Asegurar resolución alta para imágenes de Facebook/Avatares
            $imageUrl = Optimize-FacebookImageUrl $imageUrl
            
            # Fecha de publicación
            $pubDate = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            if ($item.timestamp) {
                try {
                    $epoch = New-Object DateTime 1970, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc)
                    # El timestamp de Apify a veces está en milisegundos
                    $tsVal = [double]$item.timestamp
                    if ($tsVal -gt 1000000000000) { $tsVal = $tsVal / 1000 }
                    $pubDate = $epoch.AddSeconds($tsVal).ToLocalTime().ToString("yyyy-MM-ddTHH:mm:ss")
                } catch {}
            } elseif ($item.date) {
                try {
                    $pubDate = [DateTime]::Parse($item.date).ToString("yyyy-MM-ddTHH:mm:ss")
                } catch {}
            }
            
            $newArticle = [PSCustomObject]@{
                url = $realUrl
                query = $query
                title = $title
                source = $source
                published_date = $pubDate
                summary = $postText
                sentiment = $analysis.sentiment
                sentiment_score = $analysis.score
                relevance = $relevance
                image_url = $imageUrl
                scraped_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            }
            
            $Db.news += $newArticle
            $NewFacebookCount++
            $NewNewsCount++
            Write-Host "    [+] Nuevo post FB: $source : $title ($($analysis.sentiment))" -ForegroundColor Green
        }
    }
}

# 7. Guardar Base de Datos
$Db | ConvertTo-Json -Depth 10 | Out-File -FilePath $DbPath -Encoding utf8
Write-Host "`n[Base de Datos] Guardada correctamente en $DbPath" -ForegroundColor Green

# 8. Exportar para Dashboard
$DashboardDir = Join-Path $ScriptDir "dashboard"
if (-not (Test-Path $DashboardDir)) {
    New-Item -ItemType Directory -Path $DashboardDir | Out-Null
}

$DataJsonPath = Join-Path $DashboardDir "data.json"
$DataJsPath = Join-Path $DashboardDir "data.js"

$ExportData = [PSCustomObject]@{
    news = $Db.news
    youtube = $Db.youtube
    twitter = $Db.twitter
    updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
}

# Guardar data.json
$ExportData | ConvertTo-Json -Depth 10 | Out-File -FilePath $DataJsonPath -Encoding utf8

# Guardar data.js (como variable global window.monitorData)
$jsContent = "window.monitorData = " + ($ExportData | ConvertTo-Json -Depth 10) + ";"
$jsContent | Out-File -FilePath $DataJsPath -Encoding utf8

Write-Host "[Exportación] Datos exportados para el Dashboard." -ForegroundColor Green

# 9. Actualización Automática en GitHub (para Despliegue en Netlify / Vercel)
$hasRemote = git remote
if ($null -ne $hasRemote -and $hasRemote -contains "origin") {
    Write-Host "`n[Git] Iniciando subida automática de datos a GitHub..." -ForegroundColor Yellow
    try {
        # Obtener rama actual
        $currentBranch = (git rev-parse --abbrev-ref HEAD).Trim()
        if ([string]::IsNullOrEmpty($currentBranch)) { $currentBranch = "main" }
        
        # Agregar archivos de datos cambiados
        git add database.json dashboard/data.json dashboard/data.js
        
        # Validar si hay cambios por hacer commit
        $status = git status --porcelain
        if ($status -match "database.json" -or $status -match "data.json" -or $status -match "data.js") {
            $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            git commit -m "Auto-update data: $timestamp"
            Write-Host "  [-] Realizando push a la rama $currentBranch..." -ForegroundColor Gray
            git push origin $currentBranch
            Write-Host "[Git] Datos subidos exitosamente a GitHub. ¡Tu web en Netlify/Vercel se está actualizando!" -ForegroundColor Green
        } else {
            Write-Host "[Git] No se detectaron cambios en los datos, no es necesario hacer push." -ForegroundColor Gray
        }
    } catch {
        Write-Host "[Warning] Error al subir datos a GitHub: $_" -ForegroundColor DarkYellow
    }
} else {
    Write-Host "`n[Git/Nota] No se ha configurado un repositorio remoto 'origin'. Tu sitio web local funciona, pero no se subirá a internet de forma automática hasta que vincules un repositorio remoto en GitHub." -ForegroundColor DarkGray
}

Write-Host "--------------------------------------------------" -ForegroundColor Cyan
Write-Host "Monitoreo finalizado." -ForegroundColor Cyan
Write-Host "Noticias nuevas: $NewNewsCount" -ForegroundColor Green
if ($null -ne $Config.facebook_cookies -and $Config.facebook_cookies.Count -gt 0) {
    Write-Host "Posts de Facebook nuevos: $NewFacebookCount" -ForegroundColor Green
}
Write-Host "Videos nuevos: $NewYoutubeCount" -ForegroundColor Green
Write-Host "Tweets nuevos: $NewTwitterCount" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan
