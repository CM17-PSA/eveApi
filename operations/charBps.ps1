param (
	[parameter(Mandatory)]
	[string]$charId,
	[parameter(Mandatory)]
	[string]$accessToken
)

$headers = @{
	accept = 'application/json'
	'Cache-Control' = 'no-cache'
	Authorization = "Bearer $accessToken"
}

try
{
	$bps = Invoke-RestMethod -Uri "https://esi.evetech.net/latest/characters/$($charId)/blueprints" -Method Get -Headers $headers
	return $bps
} catch
{
	$fail = Write-Error $_
	throw $fail
}
