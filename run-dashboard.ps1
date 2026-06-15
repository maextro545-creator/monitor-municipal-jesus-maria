# Servidor Local MuniWatch - Panel de Control con Calificación Manual
# Ejecución: powershell -ExecutionPolicy Bypass -File .\run-dashboard.ps1

$ScriptDir = $PSScriptRoot
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = Get-Location }

# Inicializar HttpListener
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:5000/")
$listener.Prefixes.Add("http://127.0.0.1:5000/")

try {
    $listener.Start()
} catch {
    Write-Host "[Error] No se pudo iniciar el servidor. Es posible que el puerto 5000 esté ocupado." -ForegroundColor Red
    Write-Host "Detalle: $_" -ForegroundColor Red
    exit
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "MuniWatch Dashboard Server - Servidor Iniciado" -ForegroundColor Green
Write-Host "Servidor corriendo en: http://localhost:5000/" -ForegroundColor Green
Write-Host "Presiona Ctrl+C en esta ventana para apagar el servidor." -ForegroundColor Yellow
Write-Host "==================================================" -ForegroundColor Cyan

# Abrir el navegador por defecto
Start-Process "http://localhost:5000/"

while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $req = $context.Request
        $res = $context.Response
        
        # Cabeceras CORS para permitir peticiones desde cualquier origen (e.g. desde el dashboard de producción)
        $res.AddHeader("Access-Control-Allow-Origin", "*")
        $res.AddHeader("Access-Control-Allow-Headers", "Content-Type")
        $res.AddHeader("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        
        if ($req.HttpMethod -eq "OPTIONS") {
            $res.StatusCode = 200
            $res.Close()
            continue
        }
        
        $path = $req.Url.LocalPath
        if ($path -eq "/") { $path = "/index.html" }
        
        # Endpoint para actualizar calificación manual de sentimiento
        if ($path -eq "/api/update-sentiment" -and $req.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $params = $body | ConvertFrom-Json
            
            Write-Host "[API] Solicitud de cambio de sentimiento recibida para el ID: $($params.id) -> $($params.sentiment)" -ForegroundColor Cyan
            
            $DbPath = Join-Path $ScriptDir "database.json"
            if (-not (Test-Path $DbPath)) {
                $res.StatusCode = 500
                $res.ContentType = "application/json"
                $resBytes = [System.Text.Encoding]::UTF8.GetBytes('{"error":"database.json not found"}')
                $res.OutputStream.Write($resBytes, 0, $resBytes.Length)
                $res.Close()
                continue
            }
            
            $Db = Get-Content -Raw -Path $DbPath -Encoding utf8 | ConvertFrom-Json
            $updated = $false
            
            # 1. Buscar en Prensa / Facebook (news)
            if ($params.type -eq "news") {
                foreach ($item in $Db.news) {
                    if ($item.url -eq $params.id) {
                        $item.sentiment = $params.sentiment
                        $item.sentiment_score = if ($params.sentiment -eq "positivo") { 1.0 } elseif ($params.sentiment -eq "negativo") { -1.0 } else { 0.0 }
                        $updated = $true
                        break
                    }
                }
            }
            # 2. Buscar en YouTube (youtube)
            elseif ($params.type -eq "youtube") {
                foreach ($item in $Db.youtube) {
                    if ($item.video_id -eq $params.id) {
                        $item.sentiment = $params.sentiment
                        $item.sentiment_score = if ($params.sentiment -eq "positivo") { 1.0 } elseif ($params.sentiment -eq "negativo") { -1.0 } else { 0.0 }
                        $updated = $true
                        break
                    }
                }
            }
            # 3. Buscar en Twitter (twitter)
            elseif ($params.type -eq "twitter") {
                foreach ($item in $Db.twitter) {
                    if ($item.url -eq $params.id) {
                        $item.sentiment = $params.sentiment
                        $item.sentiment_score = if ($params.sentiment -eq "positivo") { 1.0 } elseif ($params.sentiment -eq "negativo") { -1.0 } else { 0.0 }
                        $updated = $true
                        break
                    }
                }
            }
            
            if ($updated) {
                # Guardar en database.json
                $Db | ConvertTo-Json -Depth 10 | Out-File -FilePath $DbPath -Encoding utf8
                
                # Exportar para Dashboard
                $DashboardDir = Join-Path $ScriptDir "dashboard"
                $DataJsonPath = Join-Path $DashboardDir "data.json"
                $DataJsPath = Join-Path $DashboardDir "data.js"
                
                $ExportData = [PSCustomObject]@{
                    news = $Db.news
                    youtube = $Db.youtube
                    twitter = $Db.twitter
                    updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
                }
                
                # Guardar data.json y data.js
                $ExportData | ConvertTo-Json -Depth 10 | Out-File -FilePath $DataJsonPath -Encoding utf8
                $jsContent = "window.monitorData = " + ($ExportData | ConvertTo-Json -Depth 10) + ";"
                $jsContent | Out-File -FilePath $DataJsPath -Encoding utf8
                
                Write-Host "    [+] Cambios guardados localmente." -ForegroundColor Green
                
                # Sincronización asíncrona con GitHub para no congelar la petición
                Write-Host "    [+] Iniciando subida de datos a GitHub en segundo plano..." -ForegroundColor Cyan
                Start-Job -ScriptBlock {
                    param($ScriptDir, $id, $sentiment)
                    Set-Location -Path $ScriptDir
                    git add database.json dashboard/data.json dashboard/data.js
                    git commit -m "chore: calificacion manual de post a $sentiment ($id)"
                    git push origin main
                } -ArgumentList $ScriptDir, $params.id, $params.sentiment | Out-Null
                
                $res.StatusCode = 200
                $res.ContentType = "application/json"
                $resBytes = [System.Text.Encoding]::UTF8.GetBytes('{"status":"ok","message":"Sentiment updated successfully"}')
                $res.OutputStream.Write($resBytes, 0, $resBytes.Length)
            } else {
                Write-Host "    [Warning] No se encontró el item con el ID proporcionado: $($params.id)" -ForegroundColor DarkYellow
                $res.StatusCode = 404
                $res.ContentType = "application/json"
                $resBytes = [System.Text.Encoding]::UTF8.GetBytes('{"error":"Item not found"}')
                $res.OutputStream.Write($resBytes, 0, $resBytes.Length)
            }
            $res.Close()
            continue
        }
        
        # Servir archivos estáticos del Dashboard
        $localFilePath = Join-Path $ScriptDir "dashboard"
        $localFilePath = Join-Path $localFilePath ($path.TrimStart('/'))
        
        if (Test-Path $localFilePath -PathType Leaf) {
            $ext = [System.IO.Path]::GetExtension($localFilePath).ToLower()
            $contentType = "text/plain"
            if ($ext -eq ".html") { $contentType = "text/html" }
            elseif ($ext -eq ".css") { $contentType = "text/css" }
            elseif ($ext -eq ".js") { $contentType = "application/javascript" }
            elseif ($ext -eq ".json") { $contentType = "application/json" }
            elseif ($ext -eq ".png") { $contentType = "image/png" }
            elseif ($ext -eq ".jpg" -or $ext -eq ".jpeg") { $contentType = "image/jpeg" }
            elseif ($ext -eq ".svg") { $contentType = "image/svg+xml" }
            
            $res.ContentType = $contentType
            $res.StatusCode = 200
            
            # Leer bytes del archivo y enviarlos
            $fileBytes = [System.IO.File]::ReadAllBytes($localFilePath)
            $res.OutputStream.Write($fileBytes, 0, $fileBytes.Length)
        } else {
            $res.StatusCode = 404
            $resBytes = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found")
            $res.OutputStream.Write($resBytes, 0, $resBytes.Length)
        }
        $res.Close()
    } catch {
        Write-Host "[Error] Ocurrió una excepción al procesar la petición: $_" -ForegroundColor Red
        if ($null -ne $res) {
            try {
                $res.StatusCode = 500
                $res.Close()
            } catch {}
        }
    }
}
