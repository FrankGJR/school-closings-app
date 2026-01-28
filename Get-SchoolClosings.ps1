<#
.SYNOPSIS
Retrieves and parses school/organization closings from multiple sources (NBC Connecticut and WFSB).

.DESCRIPTION
This script downloads school closings pages from NBC Connecticut and WFSB, parses the HTML for
closing entries, and outputs structured PowerShell objects that include the organization
name, status/closing message, the site-reported update time, and the source.

The script also writes basic log entries to C:\export\SchoolClosings_NBCCT.txt
with timestamps in mm/dd/yyyy hh:mm:ss format.

.AUTHOR
Frank Guarino

.PARAMETER NbcClosingsUrl
The URL of the NBC Connecticut School Closings page to query.

.PARAMETER WfsbClosingsUrl
The URL of the WFSB School Closings page to query.

.PARAMETER LogDirectory
The directory where the log file (SchoolClosings_NBCCT.txt) will be stored.

.EXAMPLE
PS> .\Get-SchoolClosings.ps1

Runs the script with default settings, outputs all parsed entries to the console from both sources.

.EXAMPLE
PS> .\Get-SchoolClosings.ps1 -VerboseOutput

Runs the script with default settings and prints additional progress information to the console.
#>

param(
    [string]$NbcClosingsUrl = 'https://www.nbcconnecticut.com/weather/school-closings/',
    [string]$WfsbClosingsUrl = 'https://webpubcontent.gray.tv/wfsb/xml/WFSBclosings.html?app_data=referer_override%3D',
    [string]$LogDirectory = 'C:\export',
    [switch]$VerboseOutput,
    [string[]]$SchoolFilter = @('gengras', 'oak hill', 'solterra', 'partnership', 'edadvance', 'aces', 'aspire', 'naugatuck public', 'naugatuck schools', 'southington public', 'southington schools', 'hope academy', 'bridges of aces')
)

#region Helper Functions

function Get-CurrentTimestamp {
    [CmdletBinding()]
    param()
    return (Get-Date).ToString('MM/dd/yyyy HH:mm:ss')
}

function Write-LogMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO',
        [string]$LogFilePath
    )

    $timestamp = Get-CurrentTimestamp
    $logLine = "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message

    if ($LogFilePath) {
        try {
            Add-Content -Path $LogFilePath -Value $logLine -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to write to log file '$LogFilePath'. Error: $($_.Exception.Message)"
        }
    }

    if ($VerboseOutput) {
        Write-Host $logLine
    }
}

function Get-ClosingsFromSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [Parameter(Mandatory = $true)]
        [string]$SourceName,
        [string[]]$SchoolFilter,
        [string]$LogFilePath
    )

    try {
        Write-LogMessage -Message "Requesting URL from $SourceName : $Url" -Level 'INFO' -LogFilePath $LogFilePath
        $webResponse = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
    }
    catch {
        Write-LogMessage -Message "Failed to retrieve closings page from $SourceName . Error: $($_.Exception.Message)" -Level 'ERROR' -LogFilePath $LogFilePath
        return $null
    }

    $htmlContent = $webResponse.Content

    if ([string]::IsNullOrWhiteSpace($htmlContent)) {
        Write-LogMessage -Message "Closings page content was empty or null from $SourceName ." -Level 'WARN' -LogFilePath $LogFilePath
        return $null
    }

    # Extract update time - use different pattern based on source
    $updateTime = $null

    if ($SourceName -eq "WFSB") {
        # WFSB format: <TD CLASS="timestamp"...>UPDATED MONDAY, JAN 26 AT  6:39 PM</TD>
        $updatePattern = '<TD\s+CLASS="timestamp"[^>]*>(?<timestamp>[^<]+)</TD>'
    }
    else {
        # NBC Connecticut format
        $updatePattern = 'Update\s+(?<timestamp>[^<\r\n]+)'
    }

    $updateMatch = [regex]::Match($htmlContent, $updatePattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($updateMatch.Success) {
        $updateTime = $updateMatch.Groups['timestamp'].Value.Trim()
        Write-LogMessage -Message "Detected update time from $SourceName : $updateTime" -Level 'INFO' -LogFilePath $LogFilePath
    }

    # Parse entries - use different pattern based on source
    $regexOptions = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase `
                   -bor [System.Text.RegularExpressions.RegexOptions]::Singleline

    if ($SourceName -eq "WFSB") {
        # WFSB uses table format: <FONT CLASS="orgname">...[possibly <a>...]School Name...</a>...</FONT>: <FONT CLASS="status">Status</FONT>
        # Extract text from orgname (which may contain links), then status
        $entryPattern = '<FONT\s+CLASS="orgname"[^>]*>(?<nameraw>.*?)</FONT>[^:]*:\s*<FONT\s+CLASS="status"[^>]*>(?<status>[^<]+)</FONT>'
    }
    else {
        # NBC Connecticut and others use h4/p format
        $entryPattern = '<h4[^>]*>(?<name>.*?)</h4>\s*<p[^>]*>(?<status>.*?)</p>'
    }

    $matches = [regex]::Matches($htmlContent, $entryPattern, $regexOptions)

    if ($matches.Count -eq 0) {
        Write-LogMessage -Message "No closing entries matched the expected pattern from $SourceName ." -Level 'WARN' -LogFilePath $LogFilePath

        # Save full HTML for debugging WFSB structure
        if ($SourceName -eq "WFSB") {
            $debugFile = Join-Path -Path $LogDirectory -ChildPath "debug_${SourceName}_closings.html"
            Set-Content -Path $debugFile -Value $htmlContent -Force
            Write-Host "DEBUG: Full WFSB HTML saved to: $debugFile" -ForegroundColor Yellow
            Write-Host "DEBUG: HTML length: $($htmlContent.Length) characters" -ForegroundColor Yellow

            # Show a large sample to understand structure
            Write-Host "DEBUG: Sampling WFSB HTML (first 3000 chars):" -ForegroundColor Yellow
            Write-Host $htmlContent.Substring(0, [Math]::Min(3000, $htmlContent.Length)) -ForegroundColor Yellow
        }

        # Look for closure content and try alternative patterns
        if ($htmlContent -match 'closure|closing|closed|delay') {
            Write-Host "DEBUG: Found closure-related content in $SourceName HTML" -ForegroundColor Green

            # Try to find list items with closure info
            $liPattern = '<li[^>]*>(?<content>.*?)</li>'
            $regexOptions = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase `
                           -bor [System.Text.RegularExpressions.RegexOptions]::Singleline

            $liMatches = [regex]::Matches($htmlContent, $liPattern, $regexOptions)

            if ($liMatches.Count -gt 0) {
                Write-Host "DEBUG: Found $($liMatches.Count) <li> matches!" -ForegroundColor Green

                # Filter to closure-related list items
                $closureItems = @()
                foreach ($liMatch in $liMatches) {
                    $content = $liMatch.Groups['content'].Value
                    if ($content -match 'closed|closing|delay|closure' -and $content.Length -lt 500) {
                        $closureItems += $content
                    }
                }

                Write-Host "DEBUG: Found $($closureItems.Count) closure-related items" -ForegroundColor Green

                if ($closureItems.Count -gt 0) {
                    Write-Host "DEBUG: Sample closure items:" -ForegroundColor Yellow
                    $closureItems[0..([Math]::Min(2, $closureItems.Count-1))] | ForEach-Object {
                        Write-Host "  Item: $_" -ForegroundColor Yellow
                    }
                }
            }
        }
        return $null
    }

    Write-LogMessage -Message "Parsed $($matches.Count) closing entries from $SourceName ." -Level 'INFO' -LogFilePath $LogFilePath

    $parsedEntries = foreach ($match in $matches) {
        # For WFSB, the name may contain HTML tags (like <a> links), extract just the text
        if ($SourceName -eq "WFSB") {
            $rawName = $match.Groups['nameraw'].Value
        }
        else {
            $rawName = $match.Groups['name'].Value
        }
        $rawStatus = $match.Groups['status'].Value

        # Decode HTML entities if possible
        if ([System.Web.HttpUtility] -and [System.Web.HttpUtility]::HtmlDecode) {
            $decodedName = [System.Web.HttpUtility]::HtmlDecode($rawName)
            $decodedStatus = [System.Web.HttpUtility]::HtmlDecode($rawStatus)
        }
        else {
            $decodedName = $rawName
            $decodedStatus = $rawStatus
        }

        # Strip remaining tags and normalize whitespace
        $cleanName = ($decodedName -replace '<.*?>', '').Trim()
        $cleanStatus = ($decodedStatus -replace '<.*?>', '').Trim()

        # Filter by school name if SchoolFilter is specified
        $shouldInclude = $false
        if ($SchoolFilter.Count -eq 0) {
            $shouldInclude = $true
        }
        else {
            foreach ($schoolName in $SchoolFilter) {
                if ($cleanName -like "*$schoolName*") {
                    $shouldInclude = $true
                    break
                }
            }
        }

        if ($shouldInclude -and $cleanName.Length -gt 0 -and $cleanStatus.Length -gt 0 -and $cleanName -notmatch '<|onclick|javascript') {
            [PSCustomObject]@{
                Name       = $cleanName
                Status     = $cleanStatus
                UpdateTime = $updateTime
                Source     = $SourceName
            }
        }
    }

    return $parsedEntries
}

#endregion Helper Functions

#region Initialize Logging

if (-not (Test-Path -Path $LogDirectory)) {
    try {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }
    catch {
        Write-Warning "Unable to create log directory '$LogDirectory'. Error: $($_.Exception.Message)"
    }
}

$logFileName = 'SchoolClosings_NBCCT.txt'
$logFilePath = Join-Path -Path $LogDirectory -ChildPath $logFileName

Write-LogMessage -Message "Starting school closings retrieval from multiple sources." -Level 'INFO' -LogFilePath $logFilePath

#endregion Initialize Logging

#region Ensure HTML decoding support

try {
    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
}
catch {
    Write-LogMessage -Message "Failed to load System.Web for HTML decoding. Error: $($_.Exception.Message)" -Level 'WARN' -LogFilePath $logFilePath
}

#endregion Ensure HTML decoding support

#region Fetch and Parse Closings from Multiple Sources

$allEntries = @()

# Fetch from NBC Connecticut
$nbcEntries = Get-ClosingsFromSource -Url $NbcClosingsUrl -SourceName "NBC Connecticut" -SchoolFilter $SchoolFilter -LogFilePath $logFilePath
if ($nbcEntries) {
    $allEntries += $nbcEntries
}

# Fetch from WFSB
$wfsbEntries = Get-ClosingsFromSource -Url $WfsbClosingsUrl -SourceName "WFSB" -SchoolFilter $SchoolFilter -LogFilePath $logFilePath
if ($wfsbEntries) {
    $allEntries += $wfsbEntries
}

if ($allEntries.Count -eq 0) {
    Write-LogMessage -Message "No closing entries found from any source." -Level 'WARN' -LogFilePath $logFilePath
    Write-Warning "No closings entries were parsed from any source."
    # Always write a JSON file, even if empty
    $jsonFile = Join-Path -Path $LogDirectory -ChildPath 'school_closings.json'
    $jsonData = @{
        lastUpdated = (Get-Date).ToString('MM/dd/yyyy HH:mm:ss')
        entries = @() # Empty array
    } | ConvertTo-Json -Depth 10
    Set-Content -Path $jsonFile -Value $jsonData -Force
    Write-LogMessage -Message "Exported empty data to JSON: $jsonFile" -Level 'INFO' -LogFilePath $logFilePath
    # Also update the HTML dashboard with empty data
    $htmlTemplate = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath 'school_closings_template.html') -Raw
    $jsonCompact = @{
        lastUpdated = (Get-Date).ToString('MM/dd/yyyy HH:mm:ss')
        entries = @()
    } | ConvertTo-Json -Depth 10 -Compress
    $htmlContent = $htmlTemplate -replace '@@JSON_DATA@@', $jsonCompact
    $htmlOutputFile = Join-Path -Path $LogDirectory -ChildPath 'school_closings.html'
    Set-Content -Path $htmlOutputFile -Value $htmlContent -Force -Encoding UTF8
    Write-LogMessage -Message "Generated HTML dashboard (empty): $htmlOutputFile" -Level 'INFO' -LogFilePath $logFilePath
    return
}

#endregion Fetch and Parse Closings from Multiple Sources

#region Output

Write-LogMessage -Message "Outputting parsed closing entries to pipeline." -Level 'INFO' -LogFilePath $logFilePath

# Group by source and output with headers
$groupedBySource = $allEntries | Group-Object -Property Source

foreach ($sourceGroup in $groupedBySource) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "Source: $($sourceGroup.Name)" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan

    $sourceGroup.Group | ForEach-Object {
        Write-Host "Name: $($_.Name)"
        Write-Host "Status: $($_.Status)"
        Write-Host "Updated: $($_.UpdateTime)"
        Write-Host ""
    }
}

# Output combined table
Write-Host ""
Write-Host ("=" * 100) -ForegroundColor Green
Write-Host "Combined View - All Schools" -ForegroundColor Green
Write-Host ("=" * 100) -ForegroundColor Green
$allEntries | Format-Table -Property Name, Status, @{Label='Updated';Expression={$_.UpdateTime}}, Source -AutoSize

# Export to JSON for website
$jsonFile = Join-Path -Path $LogDirectory -ChildPath 'school_closings.json'
$jsonData = @{
    lastUpdated = (Get-Date).ToString('MM/dd/yyyy HH:mm:ss')
    entries = $allEntries
} | ConvertTo-Json -Depth 10
Set-Content -Path $jsonFile -Value $jsonData -Force
Write-LogMessage -Message "Exported data to JSON: $jsonFile" -Level 'INFO' -LogFilePath $logFilePath

# Create HTML file with embedded JSON data
$htmlTemplate = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath 'school_closings_template.html') -Raw
# Convert the JSON to a compact format for JavaScript embedding
$jsonCompact = @{
    lastUpdated = (Get-Date).ToString('MM/dd/yyyy HH:mm:ss')
    entries = $allEntries
} | ConvertTo-Json -Depth 10 -Compress
$htmlContent = $htmlTemplate -replace '@@JSON_DATA@@', $jsonCompact
$htmlOutputFile = Join-Path -Path $LogDirectory -ChildPath 'school_closings.html'
Set-Content -Path $htmlOutputFile -Value $htmlContent -Force -Encoding UTF8
Write-LogMessage -Message "Generated HTML dashboard: $htmlOutputFile" -Level 'INFO' -LogFilePath $logFilePath

#endregion Output
