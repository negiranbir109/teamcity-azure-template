param (
    [string]$templateFile = 'azuredeploy.json',
    [string]$releasesUrl
)

$cloudConfigFile = 'cloud-config.yaml'

if (!(Test-Path $cloudConfigFile)) {
    Write-Host "Cloud config file '$cloudConfigFile' is not accessible"
    exit 1
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$jsonDir = "newtonsoft.json"
$jsonPath = "$jsonDir/lib/net40/Newtonsoft.Json.dll"
if (-not (Test-Path $jsonPath)) {
    $nupkg = "newtonsoft.json.zip"
    Invoke-WebRequest -Uri https://www.nuget.org/api/v2/package/Newtonsoft.Json/11.0.2 -OutFile $nupkg
    Expand-Archive $nupkg -DestinationPath $jsonDir
    Remove-Item -Force $nupkg
}

Add-Type -Path $jsonPath

$json = Invoke-WebRequest $releasesUrl | ConvertFrom-Json

# Select last two major releases
$groups = $json.TC | Group-Object -Property majorVersion | Select-Object -First 2
$versions = New-Object System.Collections.ArrayList

foreach($group in $groups) {
    foreach($release in $group.Group) {
        $versions.add($release.version) > $null
    }
}

Write-Host "Will set the following versions: $versions"

Write-Host "Updating $templateFile file"

$replacementTokens = @{
    "%RDSHost%" = "',variables('dbServerName'),'";
    "%RDSPassword%" = "',replace(parameters('databasePassword'), '\\', '\\\\'),'";
    "%RDSDataBase%" = "',variables('dbName'),'";
    "%CORE_USER%" = "',parameters('VMAdminUsername'),'";
}

$json = (Get-Content -Path $cloudConfigFile -Raw).replace("'", "''")

foreach ($key in $replacementTokens.keys) {
    $json = $json.replace($key, $replacementTokens.Item($key))
}

$customData = "[base64(concat('$json'))]"

$template = [Newtonsoft.Json.JsonConvert]::DeserializeObject((Get-Content $templateFile -Raw), [Newtonsoft.Json.Linq.JObject])

$template.parameters.teamcityVersion.defaultValue = $versions[0]
$template.parameters.teamcityVersion.allowedValues.clear()
foreach($version in $versions) {
    $template.parameters.teamcityVersion.allowedValues.add($version)
}

$template.variables.customData = $customData

[Newtonsoft.Json.JsonConvert]::SerializeObject($template, [Newtonsoft.Json.Formatting]::Indented) | Set-Content $templateFile

Write-Host "$templateFile file was updated"