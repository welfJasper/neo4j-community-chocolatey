# Get the version list from the Neo4j Website
Function Get-VersionListFromNeo4j() {
  $neo4jDownloadURL = 'https://neo4j.com/download/other-releases/'

  $response = Invoke-WebRequest -URI $neo4jDownloadURL -UseBasicParsing

  $neo4jVersionList = ($response.links | Where-Object { ($_.href -like '*edition=community*') -and ($_.href -like '*download-thanks*') } | % {
    $url = $_.href

    if ($matches -ne $null) { $matches.Clear() }
    if ($url -match 'release=([a-zA-Z\d\.\-]+)(?:&|$)') {
      Write-Output $matches[1]
    }
  } | Select-Object -Unique)

  if ($neo4jVersionList -eq $null) { throw "Could not detect any versions on Neo4j Website" }
  Write-Output $neo4jVersionList
}

# Get the version list from this repo
Function Get-VersionListFromRepo($RootDir) {
  Get-ChildItem -Path "$RootDir\templates" |
    Where-Object { (!$_.PSIsContainer) -and ($_.name -like 'package-neo4j-community-*') } | % {
      $dirName = $_.Name

      Write-Output ($dirName.replace('package-neo4j-community-','').replace('-beta','').replace('.ps1',''))
    }
}

Function Invoke-CreateMissingTemplates($RootDir) {
  # Init
  $downloadDir = Join-Path -Path $RootDir -ChildPath 'automation\downloads'
  if (-not (Test-Path -Path $downloadDir)) { New-Item -Path $downloadDir -ItemType Directory | Out-Null }

  # Get Version lists
  $neoList = Get-VersionListFromNeo4j
  $repoList = Get-VersionListFromRepo -RootDir $RootDir

  # Find new versions
  $neoList | ForEach-Object {
    $neoVersion = $_
    if ($repoList -contains $neoVersion) {
      Write-Host "Neo4j v$($neoVersion) is already in this repository"
    } else {
      Write-Host "Creating Neo4j v$($neoVersion) template..."

      $downloadURL = "http://neo4j.com/artifact.php?name=neo4j-community-$($neoVersion)-windows.zip"
      $neoZip = Join-Path -Path $downloadDir -ChildPath "neo-$($neoVersion).zip"
      if (-not (Test-Path -Path $neoZip)) {
        Write-Host "Downloading from $downloadURL ..."
        (New-Object System.Net.WebClient).DownloadFile($downloadURL, $neoZip)
      } else {
        Write-Host "Using cached download"
      }

      Write-Host "Generating MD5 Hash..."
      $downloadHash = Get-FileHash -Path $neoZip -Algorithm MD5

      # Generate the rest of the Package Definition
      $PackageVersion = $neoVersion
      $TemplateName = ''
      if ($neoVersion -like '3.*') { $TemplateName = 'neo4j-community-v3.1' }
      if ($neoVersion -like '2.3.*') { $TemplateName = 'neo4j-community8.2' }
      # Disabled 2.2 automatic generation as it is no longer developed
      #if ($neoVersion -like '2.2.*') { $TemplateName = 'neo4j-community' }
      if ($TemplateName -eq '') { Throw "Unable to determine Template Name for Neo4j v$($neoVersion)" }

      $PrivateJavaVersion = ''
      $PrivateJreChecksumMD5 = ''
      $PrivateJavaURIDir = ''

      # Set Private JRE information
      if ($neoVersion -like '3.*') {
        $PrivateJavaVersion = "8.0.131.11"
        $PrivateJavaURIDir = "d54c1d3a095b4ff2b6607d096fa80163/"
        $PrivateJreChecksumMD5 = "9458b62000daac0f48155323185f1c4c"
      }
      if ($neoVersion -like '2.*') {
        # Neo4j 2.x series is not fully supported in Java 8, but Java 7 is no longer available.
        $PrivateJavaVersion = "8.0.131.11"
        $PrivateJavaURIDir = "d54c1d3a095b4ff2b6607d096fa80163/"
        $PrivateJreChecksumMD5 = "9458b62000daac0f48155323185f1c4c"
      }

      # Beta Version
      if ($neoVersion -notmatch ('^[\d\.]+$')) {
        # If the package version doesn't contain white-list text, append `-beta`
        if ($neoVersion -notmatch ('alpha')) {
          $PackageVersion += '-beta'
        }
        $TemplateName += '-beta'
      }

      $templateContents = @"
`$PackageDefinition = @{
  "TemplateName" = "$($TemplateName)";
  "PackageName" = "neo4j-community";
  "PackageVersion" = "$($PackageVersion)";
  "DownloadURL" = "$($downloadURL)";
  "MD5Checksum" = "$($downloadHash.Hash.ToLower())";
  "NeoZipSubdir" = "neo4j-community-$($neoVersion)";
  "NeoServerApiJarSuffix" = "$($neoVersion)";
  "PrivateJavaVersion" = "$($PrivateJavaVersion)";
  "PrivateJavaURIDir" = "$($PrivateJavaURIDir)";
  "PrivateJreChecksumMD5" = "$($PrivateJreChecksumMD5)";
}
"@
      $templateFile = Join-Path -Path "$($RootDir)\templates" -ChildPath "package-neo4j-community-$($PackageVersion).ps1"

      # Write out the template file
      Write-Host "Creating $templateFile ..."
      Out-File -InputObject $templateContents -FilePath $templateFile -Encoding ASCII -Force -Confirm:$false

      Write-Output "neo4j-community-$PackageVersion"
    }
  }
}
