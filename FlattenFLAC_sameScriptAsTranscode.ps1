function Get-FlacTags {
    param([string]$filePath)

    $tags = New-Object 'System.Collections.Hashtable' ([System.StringComparer]::OrdinalIgnoreCase)

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "ffprobe"
    $startInfo.Arguments = "-v error -show_entries format_tags -of default=noprint_wrappers=1:nokey=0 `"$filePath`""
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false
    $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $process.Start() | Out-Null
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($stderr -and $stderr.Trim() -ne "") {
        Write-Warning "ffprobe error for: $filePath`n$stderr"
        return $tags
    }

    foreach ($line in $stdout -split "`n") {
        if ($line -match '^TAG:(.*?)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            if ($key -and $value) {
                $tags[$key] = $value
            }
        }
    }

    return $tags
}



# === Helper function for case-insensitive tag lookup ===
function Get-TagValue {
    param($tags, $key)
    $keyLC = $key.ToLower()
    if ($tags.ContainsKey($keyLC)) {
        return $tags[$keyLC]
    } else {
        return $null
    }
}



# === Helper function to sanitize for path and file names ===
function Sanitize-ForPath {
    param($inputString)

    # Replace forbidden and problematic characters with "_"
    $output = $inputString -replace '[\\/:\*\?"<>\|,\.&\(\)\[\]]', '_'

    # Replace "_ " with "_"
    $output = $output -replace '_\s', '_'

    # Replace " _" with "_"
    $output = $output -replace '\s_', '_'

    # Replace multiple consecutive underscores with single underscore
    $output = $output -replace '_{2,}', '_'

    # Replace all remaining spaces with underscores
    $output = $output -replace '\s', '_'

    # Trim underscores from start/end
    $output = $output.Trim('_')

    return $output
}

# === Set up target folder ===
$targetRoot = "D:\av_media\audio_media\MyMusic_FLAC_Flat"

# === Initialize counters ===
$totalFilesToProcess = 0
$currentFileIndex = 0
$skippedFiles = 0
$copiedFiles = 0

# === Main loop with heartbeat progress ===
$files = Get-ChildItem -Path "D:\av_media\audio_media\MyMusic_flac_redo" -Recurse -Include *.flac

$totalFilesToProcess = $files.Count

Write-Host "=== Starting FLAC flatten copy ==="
Write-Host "Total FLAC files to process: $totalFilesToProcess"
Write-Host "Target root: $targetRoot"

foreach ($file in $files) {

    $currentFileIndex++
    if ($currentFileIndex % 100 -eq 0) {
        Write-Host "Processing file $currentFileIndex of $totalFilesToProcess"
    }

    # Read tags
    $tags = Get-FlacTags $file.FullName

    # === Fallback logic ===
    $album = Get-TagValue $tags "Album"
    if (-not $album) { $album = "UnknownAlbum" }

    $isCompilation = $false
    if ($tags['COMPILATION'] -eq '1' -or
        ($tags['COMPILATION'] -match 'true') -or
        ($tags['AlbumArtist'] -match 'Various Artists') -or
        ($tags['album_artist'] -match 'Various Artists')) {
        $isCompilation = $true
    }

    if ($isCompilation) {
        $composer = "Various Artists"
    } else {
        $composer = Get-TagValue $tags "Composer"
        if (-not $composer) { $composer = Get-TagValue $tags "AlbumArtist" }
        if (-not $composer) { $composer = Get-TagValue $tags "album_artist" }
        if (-not $composer) { $composer = Get-TagValue $tags "Artist" }
        if (-not $composer) { $composer = "UnknownComposer" }
    }

    if ($isCompilation) {
        $performer = "Various Artists"
    } else {
        $performer = Get-TagValue $tags "AlbumArtist"
        if (-not $performer) { $performer = Get-TagValue $tags "album_artist" }
        if (-not $performer) { $performer = Get-TagValue $tags "Artist" }
        if (-not $performer) { $performer = Get-TagValue $tags "Performer" }
        if (-not $performer) { $performer = "UnknownPerformer" }
    }

    # === Sanitize ===
    $composerSanitized = Sanitize-ForPath $composer
    $albumSanitized = Sanitize-ForPath $album
    $performerSanitized = Sanitize-ForPath $performer
    $trackNameSanitized = Sanitize-ForPath ([System.IO.Path]::GetFileNameWithoutExtension($file.Name))

    # Build target
    $proposedFolder = "$composerSanitized-$albumSanitized[$performerSanitized]"
    $proposedFile = "$trackNameSanitized.flac"
    $targetFolder = Join-Path $targetRoot $proposedFolder
    $targetFilePath = Join-Path $targetFolder $proposedFile

    # Debug
    Write-Host "`n[DEBUG] Checking file path:"
    Write-Host "[DEBUG] targetFilePath: $targetFilePath"
    Write-Host "[DEBUG] Directory exists? " (Test-Path -LiteralPath $targetFolder)
    Write-Host "[DEBUG] File exists? " (Test-Path -LiteralPath $targetFilePath)

    # List folder contents for verification
    Write-Host "[DEBUG] Files in folder:"
    Get-ChildItem -LiteralPath $targetFolder -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host " - $($_.Name)"
    }

    # Create target folder if needed
    $null = New-Item -ItemType Directory -Path $targetFolder -Force -ErrorAction SilentlyContinue

    # Check whether to copy
    if (Test-Path -LiteralPath $targetFilePath -PathType Leaf) {
        $flacModified = (Get-Item -LiteralPath $file.FullName).LastWriteTimeUtc
        $targetModified = (Get-Item -LiteralPath $targetFilePath).LastWriteTimeUtc
        $delta = ($targetModified - $flacModified).TotalSeconds

        Write-Host "`n--- Timestamp Check ---"
        Write-Host "FLAC: $flacModified"
        Write-Host "FLAT : $targetModified"
        Write-Host "Δ t : $([math]::Round($delta, 2)) seconds"

        if ($delta -ge 1) {
            Write-Host "⏭️  Skipping (existing newer): $trackNameSanitized"
            $skippedFiles++
            continue
        } else {
            Write-Host "🔁 Re-copying (FLAC newer): $trackNameSanitized"
        }
    } else {
        Write-Warning "⚠️  FLAC file does not exist in target: $targetFilePath"
        Write-Host "🆕 New file: $trackNameSanitized"
    }

    # === Copy the FLAC to target ===
    Write-Host "📝 Copying: $($file.FullName) --> $targetFilePath"
    Copy-Item -Path $file.FullName -Destination $targetFilePath -Force
    $copiedFiles++
}

# === Summary ===
Write-Host "=== FLAC Flatten Summary ==="
Write-Host "Total FLAC files processed: $totalFilesToProcess"
Write-Host "FLAC files copied: $copiedFiles"
Write-Host "Files skipped (already existed and newer): $skippedFiles"
Write-Host "Target root: $targetRoot"

