param (
	[parameter(Mandatory)]
	[string]$charId
)

$headers = @{
	accept = 'application/json'
	'Cache-Control' = 'no-cache'
}
$CharacterDetails = Invoke-RestMethod -Uri "https://esi.evetech.net/latest/characters/$($charId)/" -Method Get -Headers $headers
return $CharacterDetails
