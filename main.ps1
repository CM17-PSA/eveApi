# Confirm ability to return current status of Eve to ensure that connections are being processed.

Write-Output "Confirming ESI is responding on status check and reporting Server Version";

$CoreStatus = Invoke-WebRequest -Method Get -Uri https://esi.evetech.net/v1/status | Select-Object StatusCode,Content;
if($CoreStatus.StatusCode -ne 200)
{
	Write-Output "ESI did not provide a valid response back.";
	return;
}
$Version = $CoreStatus.Content | ConvertFrom-Json | Select-Object -ExpandProperty server_version;
Write-Output "ESI reporting Server Version $Version";

$clientId = 'populate your own, look it up in the Eve docs to find how'
$clientSecret = 'bad practice hardcoding values, but fuck it'
$ongoing = $true


Import-Module "$PSScriptRoot/operations/core.ps1"

try
{
	$codeChallenge = New-PKCE
	$state = New-State
	$expectedState = $state
} catch
{
	$fail = Write-Error $_
	throw $fail
}
if((Get-ChildItem $PSScriptRoot/model).Count -eq 0)
{
	try
	{
		New-Authentication -state $state -codeChallenge $codeChallenge -clientID $clientId -clientSecret $clientSecret
	} catch
	{
		$fail = Write-Error $_
		throw $fail
	}
}

enum Operations
{
	Shutdown = 0
	AddCharacter = 1
	SelectCharacter = 2
}

enum AuthenticatedOperations
{
	Back = 0
	ShowPublicDetails = 1
	ListBlueprints = 2
}

while($ongoing)
{
	if(!$authenticated)
	{
		$op = Read-Host ("What would we like to do?
0. Shutdown
1. Add New Character
2. Select Existing Character?")

		switch($op)
		{
			'0'
   {
				$action = [Operations]::Shutdown
				Write-Output "Gracefully Exiting..."
				$ongoing = $false
				break;
			}
			'1'
			{
				$action = [Operations]::AddCharacter
				Write-Output "You have selected to Add a New Character..."
				New-Authentication -state $state -codeChallenge $codeChallenge -clientID $clientId -clientSecret $clientSecret
				break;
			}
			'2'
			{
				$action = [Operations]::SelectCharacter
				Write-Output "YOu have selected to leverage an existing Authentication..."
				Get-Character
				$activeChar = Select-Character
				$authenticated = $true
				break;
			}
			default
			{
				Write-Output "Invalid submission received. I accept Integers and am not sophisticated enough to identify what you fed me that was wrong, but I don't like it."
			}
		}
	}
	if($authenticated)
	{
		$expiryTime = (Get-Date $($activeChar.ExpiresOn)).ToUniversalTime()
		$currentTime = (Get-Date).ToUniversalTime()
		if($expiryTime.AddMinutes(-2) -gt $currentTime)
		{
			Refresh-Authentication -clientId $clientId -refreshToken $activeChar.refreshToken -codeVerifier $activeChar.verifier
		}
		$authOp = Read-Host ("With Character {0}, what operations would you like to complete?
0. Go back
1. Show public details
2. List available Blueprints" -f $activeChar.CharacterID)
		switch ($authOp)
		{
			'0'
			{
				Write-Output "Back to Main Menu..."
				$authenticated = $false
				break;
			}
			'1'
			{
				Write-Output ("Collecting the Public Details for {0}" -f $activeChar.CharacterID)
				try
				{
					$character = & $PSScriptRoot/operations/pubCharDetails.ps1 -CharId $activeChar.CharacterID
				} catch
				{
					$fail = Write-Error $_
					throw $fail
				}
				if($character)
				{
					Write-Output ("Character {0} born on {1} is {2} and provides the following bio: {3}" -f $character.name,$character.birthday,$character.gender,$character.description.Replace('<br>',"`r`n"))
				}
				break;
			}
			'2'
			{
				Write-Output ("Colelcting available Blueprints for {0}" -f $activeChar.CharacterID)
				try
				{
					& $PSscriptRoot/operations/charBps.ps1 -CharId $activeChar.CharacterID -accessToken $activeChar.Token
				} catch
				{
					$fail = Write-Error $_
					throw $fail
				}
				break;
			}
			default
			{
				Write-Output "Told you before. I am not intelligent. The Gippity has made you so week you cannot process basic instructions. Use your brain, or uninstall."
				break;
			}
		}
	}
}
