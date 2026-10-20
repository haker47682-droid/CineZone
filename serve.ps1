# Lanceur du site CineZone en local (aucune dependance : Python/Node non requis)
# Usage :  powershell -ExecutionPolicy Bypass -File .\serve.ps1
param(
    [int]$Port = 8080,
    # Origine du backend d'origine, utilise pour les appels /api/* du site
    [string]$ApiOrigin = "https://senpai.watch"
)

$root = $PSScriptRoot
$url  = "http://127.0.0.1:$Port/"

# Nom de marque construit par code : evite tout probleme d'encodage du fichier .ps1
$brand = 'Cin' + [char]0xE9 + 'Zone'

$mime = @{
    '.html'        = 'text/html; charset=utf-8'
    '.js'          = 'application/javascript; charset=utf-8'
    '.mjs'         = 'application/javascript; charset=utf-8'
    '.css'         = 'text/css; charset=utf-8'
    '.json'        = 'application/json; charset=utf-8'
    '.webmanifest' = 'application/manifest+json; charset=utf-8'
    '.svg'         = 'image/svg+xml'
    '.png'         = 'image/png'
    '.jpg'         = 'image/jpeg'
    '.jpeg'        = 'image/jpeg'
    '.webp'        = 'image/webp'
    '.gif'         = 'image/gif'
    '.ico'         = 'image/x-icon'
    '.woff'        = 'font/woff'
    '.woff2'       = 'font/woff2'
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($url)

try {
    $listener.Start()
} catch {
    Write-Host "Impossible de demarrer sur $url : $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "$brand est en ligne sur $url" -ForegroundColor Green
Write-Host "Dossier servi : $root"
Write-Host "Ctrl+C pour arreter."

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    try {
        $path = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath)
        if ([string]::IsNullOrEmpty($path) -or $path -eq '/') { $path = '/index.html' }

        # Les appels API du site (navigation, fiches, lecteurs) sont relayes
        # vers le backend d'origine, sinon le site ne peut charger que l'accueil.
        if ($path -like '/api/*') {
            $target = "$ApiOrigin$path$($ctx.Request.Url.Query)"
            try {
                $req = [System.Net.HttpWebRequest]::Create($target)
                $req.Method  = $ctx.Request.HttpMethod
                $req.UserAgent = 'Mozilla/5.0'
                $req.Accept  = 'application/json, text/plain, */*'
                $req.Timeout = 30000
                $resp   = $req.GetResponse()
                $status = [int]$resp.StatusCode
                $ct     = $resp.ContentType
                $reader = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
                $body   = $reader.ReadToEnd()
                $reader.Close()
                $resp.Close()

                # Harmonise le nom de marque renvoye par le backend
                if ($ct -match 'json|text|javascript') {
                    $body = $body.Replace('Senpai Stream', $brand).Replace('SenpaiStream', $brand)
                }

                $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                $ctx.Response.StatusCode  = $status
                $ctx.Response.ContentType = $ct
                $ctx.Response.ContentLength64 = $bytes.Length
                $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            } catch {
                $ctx.Response.StatusCode = 502
                $ctx.Response.ContentType = 'application/json'
                $bytes = [System.Text.Encoding]::UTF8.GetBytes('{"error":"api proxy unavailable"}')
                $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            }
            $ctx.Response.OutputStream.Close()
            continue
        }

        $file = Join-Path $root ($path.TrimStart('/') -replace '/', '\')

        # Routes de l'application (ex: /watch/tv/1416) -> index.html
        if (-not (Test-Path $file -PathType Leaf)) {
            $file = Join-Path $root 'index.html'
        }

        $bytes = [System.IO.File]::ReadAllBytes($file)
        $ext   = [System.IO.Path]::GetExtension($file).ToLower()
        $ctx.Response.StatusCode = 200
        $ctx.Response.ContentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
        $ctx.Response.ContentLength64 = $bytes.Length
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } catch {
        $ctx.Response.StatusCode = 500
    } finally {
        $ctx.Response.OutputStream.Close()
    }
}
