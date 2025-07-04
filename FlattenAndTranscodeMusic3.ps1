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

# === Target MP3 root folder ===
$targetRoot = "D:\av_media\audio_media\MyMusic_mp3_flat"

# === Initialize counters ===
$totalFilesToProcess = 0
$currentFileIndex = 0
$skippedFiles = 0
$encodedFiles = 0

# === Main loop with heartbeat progress ===
$files = Get-ChildItem -Path "D:\av_media\audio_media\MyMusic_flac_redo" -Recurse -Include *.flac

$totalFilesToProcess = $files.Count

Write-Host "=== Starting FLAC to MP3 conversion ==="
Write-Host "Total FLAC files to process: $totalFilesToProcess"
Write-Host "Target root: $targetRoot"

foreach ($file in $files) {

    $currentFileIndex++
    if ($currentFileIndex % 100 -eq 0) {
        Write-Host "Processing file $currentFileIndex of $totalFilesToProcess"
    }

    # Read tags using your function
    $tags = Get-FlacTags $file.FullName

# === Field fallback logic ===

# Album
$album = Get-TagValue $tags "Album"
if (-not $album) { $album = "UnknownAlbum" }

# Detect compilation
$isCompilation = $false
if ($tags['COMPILATION'] -eq '1' -or ($tags.ALBUMARTIST -match 'Various Artists')) {
    $isCompilation = $true
}

# Composer logic
if ($isCompilation) {
    $composer = "Various Artists"
} else {
    $composer = Get-TagValue $tags "Composer"
    if (-not $composer) { $composer = Get-TagValue $tags "AlbumArtist" }
    if (-not $composer) { $composer = Get-TagValue $tags "Artist" }
    if (-not $composer) { $composer = "UnknownComposer" }
}

# Performer logic
if ($isCompilation) {
    $performer = "Various Artists"
} else {
    $performer = Get-TagValue $tags "AlbumArtist"
    if (-not $performer) { $performer = Get-TagValue $tags "Artist" }
    if (-not $performer) { $performer = Get-TagValue $tags "Performer" }
    if (-not $performer) { $performer = "UnknownPerformer" }
}


########################

    # === Sanitize fields for folder/file use ===
    $composerSanitized = Sanitize-ForPath $composer
    $albumSanitized = Sanitize-ForPath $album
    $performerSanitized = Sanitize-ForPath $performer
    $trackNameSanitized = Sanitize-ForPath ([System.IO.Path]::GetFileNameWithoutExtension($file.Name))


    # Build ProposedFolder and ProposedFile
    $proposedFolder = "$composerSanitized-$albumSanitized[$performerSanitized]"
    $proposedFile = "$trackNameSanitized.mp3"

    # Full target path
    $targetFolder = Join-Path $targetRoot $proposedFolder
    $targetFilePath = Join-Path $targetFolder $proposedFile

# Debug print
Write-Host "`n[DEBUG] Checking file path:"
Write-Host "[DEBUG] targetFilePath: $targetFilePath"
Write-Host "[DEBUG] Directory exists? " (Test-Path -LiteralPath $targetFolder)
Write-Host "[DEBUG] File exists? " (Test-Path -LiteralPath $targetFilePath)

# Also list files in folder to verify manually
Write-Host "[DEBUG] Files in folder:"
Get-ChildItem -LiteralPath $targetFolder | ForEach-Object {
    Write-Host " - $($_.Name)"
}



    # Create target folder if needed (safe version — no warning)
    $null = New-Item -ItemType Directory -Path $targetFolder -Force -ErrorAction SilentlyContinue




# === Decide whether to transcode ===
Write-Host "`n[DEBUG] Looking for: $targetFilePath"
Write-Host "[DEBUG] Exists? " (Test-Path -LiteralPath $targetFilePath)


if (Test-Path -LiteralPath $targetFilePath) {
    $flacModified = (Get-Item -LiteralPath $file.FullName).LastWriteTimeUtc
    $mp3Modified = (Get-Item -LiteralPath $targetFilePath).LastWriteTimeUtc

    $delta = ($mp3Modified - $flacModified).TotalSeconds

    Write-Host "`n--- Timestamp Check ---"
    Write-Host "FLAC: $flacModified"
    Write-Host "MP3 : $mp3Modified"
    Write-Host "Δ t : $([math]::Round($delta, 2)) seconds"

    if ($delta -ge 1) {
        Write-Host "⏭️  Skipping (MP3 is newer): $trackNameSanitized"
        $skippedFiles++
        continue
    } else {
        Write-Host "🔁 Re-encoding (FLAC newer): $trackNameSanitized"
    }
} else {
    Write-Warning "⚠️  MP3 file does not exist: $targetFilePath"
    Write-Host "🆕 New file: $trackNameSanitized"
}


# === Transcode FLAC to MP3 CBR 320 kbps ===
Write-Host "🎧 Encoding: $($file.FullName) --> $targetFilePath"
& ffmpeg -hide_banner -loglevel error -y -i $file.FullName -codec:a libmp3lame -b:a 320k $targetFilePath
$encodedFiles++

 }  # ✅ This closes the foreach loop

# === Summary ===
Write-Host "=== Flatten and Transcode Summary ==="
Write-Host "Total FLAC files processed: $totalFilesToProcess"
Write-Host "MP3 files encoded: $encodedFiles"
Write-Host "Files skipped (already existed): $skippedFiles"
Write-Host "Target root: $targetRoot"
