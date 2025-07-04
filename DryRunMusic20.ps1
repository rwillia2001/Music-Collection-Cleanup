# === Set UTF-8 console output encoding (PowerShell 7+ honors this) ===
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# === Case-insensitive tag fetch ===
function Get-TagValue {
    param($tags, $key)
    if (-not $tags) { return $null }

    $entry = $tags.GetEnumerator() | Where-Object { $_.Key -ieq $key } | Select-Object -First 1
    return $entry?.Value
}

# === Get tags from a FLAC file using ffprobe (UTF-8 safe, with TAG: stripping) ===
function Get-FlacTags {
    param([string]$filePath)

    $tags = New-Object 'System.Collections.Hashtable' ([System.StringComparer]::OrdinalIgnoreCase)

    # Force use of UTF-8 output for ffprobe, and quote path for Windows shell compatibility
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


# === Path sanitizer for folder/file naming ===
function Sanitize-ForPath {
    param($inputString)

    $output = $inputString -replace '[\\/:\*\?"<>\|,\.&\(\)\[\]]', '_'
    $output = $output -replace '_\s', '_' -replace '\s_', '_'
    $output = $output -replace '_{2,}', '_' -replace '\s', '_'
    return $output.Trim('_')
}


# === Helper function for case-insensitive tag lookup ===
function Get-TagValue {
    param($tags, $key)
    return ($tags.GetEnumerator() | Where-Object { $_.Name -ieq $key } | Select-Object -ExpandProperty Value -First 1)
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

# === Control whether results are printed to terminal after processing ===
$showTerminalOutput = $false  # Set to $true for DEBUG runs

# === Initialize summary counters ===
$totalFilesChecked = 0
$missingComposerCount = 0
$missingAlbumCount = 0
$missingPerformerCount = 0

# === Main loop with heartbeat progress ===
$results = @()
$files = Get-ChildItem -Path "D:\av_media\audio_media\MyMusic_flac_redo" -Recurse -Filter *.flac -File


foreach ($file in $files) {
    $filePath = $file.FullName

    # Run ffprobe and capture stdout and stderr
    $ffprobeOutput = & ffprobe -v error -show_entries format_tags -of default=noprint_wrappers=1:nokey=0 "$filePath" 2>&1

    # Look for actual metadata fields
    $hasTags = $ffprobeOutput -match "title=.*" -or `
                $ffprobeOutput -match "album=.*" -or `
                $ffprobeOutput -match "artist=.*"

    # Known false positive: embedded artwork decoding error
    $hasArtworkError = $ffprobeOutput -match "mjpeg.*unable to decode APP"

    if (-not $hasTags -and -not $hasArtworkError) {
        Write-Warning "⚠️  No tags found for: $filePath"

        $results += [PSCustomObject]@{
            FilePath = $filePath
            Status   = "Missing tags"
        }
    } else {
        Write-Host "✅ Tags OK: $filePath"
    }
}

# Save to CSV (optional)
if ($results.Count -gt 0) {
    $results | Export-Csv -Path "missing_tags_report.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "📄 Report saved to missing_tags_report.csv"
} else {
    Write-Host "🎉 All files passed the tag check!"
}


$totalFilesToProcess = $files.Count
$currentFileIndex = 0

Write-Host "=== Starting processing of $totalFilesToProcess files ==="

foreach ($file in $files) {
if ($tags.Count -eq 0) {
    Write-Warning "⚠️  No tags found for: $($file.FullName)"
}
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

    # Composer fallback
    $composer = Get-TagValue $tags "Composer"
    if (-not $composer) { $composer = Get-TagValue $tags "AlbumArtist" }
    if (-not $composer) { $composer = Get-TagValue $tags "Artist" }
    if (-not $composer) { $composer = "UnknownComposer" }

    # Performer fallback
    $performer = Get-TagValue $tags "Performer"
    if (-not $performer) { $performer = Get-TagValue $tags "AlbumArtist" }
    if (-not $performer) { $performer = Get-TagValue $tags "Artist" }
    if (-not $performer) { $performer = "UnknownPerformer" }

    # === Sanitize fields for folder/file use ===
    $composerSanitized = Sanitize-ForPath $composer
    $albumSanitized = Sanitize-ForPath $album
    $performerSanitized = Sanitize-ForPath $performer
    $trackNameSanitized = Sanitize-ForPath $file.BaseName

    # Build ProposedFolder and ProposedFile
    $proposedFolder = "$composerSanitized-$albumSanitized[$performerSanitized]"
    $proposedFile = "$trackNameSanitized.mp3"

    # Calculate FolderPathLength
    $phonePrefix = "/storage/emulated/0/Music/MyM/"
    $folderPathLength = ($phonePrefix + $proposedFolder).Length

    # === Warnings block ===
    $warnings = @()
    if (-not $composer -or $composer.Trim() -eq "") { $warnings += "Missing Composer" }
    if (-not $album -or $album.Trim() -eq "") { $warnings += "Missing Album" }
    if (-not $performer -or $performer.Trim() -eq "") { $warnings += "Missing Performer" }
    if ($folderPathLength -gt 240) { $warnings += "Folder path too long ($folderPathLength chars)" }

# === Update summary counters ===
$totalFilesChecked++

if ($composer -eq "UnknownComposer") { $missingComposerCount++ }
if ($album -eq "UnknownAlbum") { $missingAlbumCount++ }
if ($performer -eq "UnknownPerformer") { $missingPerformerCount++ }


    # Build output object
    $results += [PSCustomObject]@{
        SourcePath = $file.FullName
        Composer = $composer
        Album = $album
        Performer = $performer
        ProposedFolder = $proposedFolder
        ProposedFile = $proposedFile
        FolderPathLength = $folderPathLength
        Warnings = $warnings -join "; "
    }
}

# === Export CSV ===
$csvPath = "C:\Users\rwill\DryRunMusicReport_v4.csv"
$results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

# Optional: show results in terminal if enabled
if ($showTerminalOutput) {
    Write-Host "=== Showing results ==="
    $results | ForEach-Object {
        Write-Host "SourcePath       : $($_.SourcePath)"
        Write-Host "Composer         : $($_.Composer)"
        Write-Host "Album            : $($_.Album)"
        Write-Host "Performer        : $($_.Performer)"
        Write-Host "ProposedFolder   : $($_.ProposedFolder)"
        Write-Host "ProposedFile     : $($_.ProposedFile)"
        Write-Host "FolderPathLength : $($_.FolderPathLength)"
        Write-Host "Warnings         : $($_.Warnings)"
        Write-Host "------------------------------------"
    }
}

# === Summary output ===
Write-Host "=== Dry Run Summary ==="
Write-Host "Total FLAC files checked: $totalFilesChecked"
Write-Host "Missing Composer: $missingComposerCount"
Write-Host "Missing Album: $missingAlbumCount"
Write-Host "Missing Performer: $missingPerformerCount"
Write-Host "CSV report saved to: $csvPath"
