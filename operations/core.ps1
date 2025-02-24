function New-PKCE
{
	# Generate a random code verifier; 43 to 128 characters
	$codeVerifier = [System.Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
	$codeVerifier = $codeVerifier.TrimEnd('=').Replace('=', '-').Replace('/','_') #URL safe encode
	#GenSHa256
	$sha256 = [System.Security.Cryptography.SHA256]::create()
	$hashed = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($codeVerifier))
	$codeChallenge = [System.Convert]::ToBase64String($hashed)
	$codeChallenge = $codeChallenge.TrimEnd('=').Replace('+','-').Replace('/','_') #URL Safe

	return @{
		CodeVerifier = $codeVerifier
		CodeChallenge = $codeChallenge
	}
}

function New-State
{
	# Generate a random 16-byte state value
	$stateBytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(16)
	$state = [System.Convert]::ToBase64String($stateBytes)
	$state = $state.TrimEnd('=').Replace('+', '-').Replace('/', '_')  # URL-safe base64
	return $state
}


function Get-AuthorizationUrl
{
	param (
		[string]$clientId = '75dbdd81cf6e4a8b964411f91ee0be73',
		[string]$redirectUri,
		[string]$state,
		[string]$codeChallenge
	)

	$encodedRedirectUri = [System.Web.HttpUtility]::UrlEncode($redirectUri)
	$scopes = @(
		"publicData",
		"esi-location.read_location.v1",
		"esi-wallet.read_character_wallet.v1",
		"esi-search.search_structures.v1",
		"esi-universe.read_structures.v1",
		"esi-assets.read_assets.v1",
		"esi-ui.write_waypoint.v1",
		"esi-industry.read_character_jobs.v1",
		"esi-markets.read_character_orders.v1",
		"esi-characters.read_blueprints.v1",
		"esi-contracts.read_character_contracts.v1",
		"esi-industry.read_character_mining.v1",
		"esi-characterstats.read.v1"
	)
	$url = "https://login.eveonline.com/v2/oauth/authorize"
	$url += "?response_type=code"
	$url += "&client_id=$clientId"
	$url += "&redirect_uri=$($encodedRedirectUri)"
	$url += "&scope=$($scopes -join ' ')"
	$url += "&code_challenge=$codeChallenge"
	$url += "&code_Challenge_method=S256"
	$url += "&state=$state"

	return $url
}

function Start-Listener
{
	param (
		[string]$redirectUri,
		[string]$expectedState
	)

	$listener = New-Object System.Net.HttpListener
	$listener.Prefixes.Add($redirectUri)
	$listener.Start()

	Write-Information "Listening for Callback..."

	$context = $listener.GetContext()
	Write-Information "Callback received..."
	$queryString = $context.Request.Url.Query
	Write-Information "Setting Response Code..."
	$context.Response.StatusCode = 200
	Write-Information "Closing session..."
	$context.Response.Close()

	$queryParams = @{}
	Write-Information "Defining keys..."
	$queryString.TrimStart('?') -split '&' | Foreach-Object {
		$keyValue = $_ -split '='
		if($keyValue.Length -eq 2)
		{
			Write-Debug "Saving $($keyValue[0]):$($keyValue[1])"
			$queryParams[$keyValue[0]] = $keyValue[1]
		}
	}
	$receivedState = $queryParams['state']
	Write-Information "Confirmed state code received: $receivedState"
	if($receivedState -ne $expectedState)
	{
		Write-Error "Error: State mismatch. Received: $receivedState, but expected $expectedState."
		return $null
	}

	$authorizationCode = $queryParams['code']
	Write-Information "Received: $authorizationCode"
	return $authorizationCode
}

function Get-AccessToken
{
	param (
		[string]$authorizationCode,
		[string]$clientId,
		[string]$clientSecret,
		[string]$redirectUri,
		[string]$codeVerifier
	)

	$url = 'https://login.eveonline.com/v2/oauth/token'

	$body = @{
		grant_type = 'authorization_code'
		code = $authorizationCode
		client_id = $clientId
		client_secret = $clientSecret
		redirect_uri = $redirectUri
		code_verifier = $codeVerifier
	}

	$headers = @{
		"Content-Type" = "application/x-www-form-urlencoded"
	}
	
	$response = Invoke-RestMethod -uri $url -Method Post -body $body -Headers $headers
	return $response
}

function Refresh-Authentication
{
	param(
		[parameter(Mandatory)]
		[string]$clientId,
		[parameter(Mandatory)]
		[string]$refreshToken,
		[parameter(Mandatory)]
		[string]$codeVerifier
	)

	$url = 'https://login.eveonline.com/v2/oauth/token'
	$headers = @{
		'Content-Type' = 'application/x-www-form-urlencoded'
	}
	$body = @{
		grant_type = 'refresh_token'
		refresh_token = $refreshToken
		client_id = $clientId
		code_verifier = $codeVerifier
	}
	$response = Invoke-RestMethod -uri $url -Method Post -body $body -Headers $headers
	$AuthenticatedCharacter = Set-CharacterDefinition -accessToken $response.access_token
	Save-CharacterDefinition -accessToken $response.access_token -refreshToken $response.refresh_token -characterValidation $AuthenticatedCharacter -codeVerifier $codeChallenge.CodeVerifier
}

function Set-CharacterDefinition
{
	param (
		[string]$accessToken
	)

	$url = 'https://esi.evetech.net/verify'
	$header = @{
		"Authorization" = "Bearer $accessToken"
	}
	$validationStatus = Invoke-RestMethod -Method Get -Uri $url -Headers $header
	if($validationStatus.ExpiresOn -gt (Get-Date).AddMinutes(+1))
	{
		if(!(Test-Path $PSScriptRoot/../model/$($validationStatus.CharacterName).json))
		{
			New-Item $PSScriptRoot/../model/$($validationStatus.CharacterName).json
		}
		return $validationStatus
	}
}

function Save-CharacterDefinition
{
	param (
		[string]$accessToken,
		[string]$refreshToken,
		[string]$codeVerifier,
		$characterValidation
	)
	$charName = $characterValidation.CharacterName
	$charStore = Get-Item $PSScriptRoot/../model/$($charName).json
	$character = @{
		CharacterID = $characterValidation.CharacterID
		ExpiresOn = $characterValidation.ExpiresOn
		Token = $accessToken
		refreshToken = $refreshToken
		verifier = $codeVerifier
	}
	
	Set-Content $charStore -Value ($Character | ConvertTo-Json)
}

function New-Authentication
{
	param (
		[string]$state,
		[string]$clientID,
		[string]$clientSecret,
		$codeChallenge
	)
	try
	{
		$authorizationUrl = Get-AuthorizationUrl -redirectUri 'http://localhost/indy_callback/' -codeChallenge $codeChallenge.codeChallenge -state $state
		Write-Output "Please visit this URL to authenticate: $authorizationUrl"
		$authorizationCode = Start-Listener -redirectUri "http://localhost/indy_callback/" -expectedState $expectedState
	} catch
	{
		$fail  = Write-Error $_
		return $fail
	}


	Write-Debug "Authorization code received: $authorizationCode"
	try
	{
		$accessTokenResponse = Get-AccessToken -authorizationCode $authorizationCode -clientId $clientId -clientSecret $clientSecret -redirectUri 'http://localhost/indy_callback/' -codeVerifier $codeChallenge.CodeVerifier
	} catch
	{
		$fail  = Write-Error $_
		return $fail
	}
	Write-Debug "AccessToken: $($accessTokenResponse.access_token)"
	Write-Output ($accessTokenResponse | ConvertTo-Json -depth 25)
	$AuthenticatedCharacter = Set-CharacterDefinition -accessToken $accessTokenResponse.access_token
	Save-CharacterDefinition -accessToken $accessTokenResponse.access_token -refreshToken $accessTokenResponse.refresh_token -characterValidation $AuthenticatedCharacter -codeVerifier $codeChallenge.CodeVerifier
}

function Get-Character
{
	Write-Output "Listing currently stored Character Definitions..."
	$authChar = Get-ChildItem $PSScriptRoot/../model/
	"Identified the following Available Characters:"
	"|Index|Character|Auth Expires|"
	$i = 0
	$characters = @()
	foreach($Char in $authChar)
	{
		$data = Get-Content $Char | ConvertFrom-Json -AsHashtable
		$characters += ("|{0}|{1}|{2}|" -f $i,$Char.Name.Replace('.json',''),$data.ExpiresOn)
		$i++
	}
	$characters
}

function Select-Character
{
	$authChar = Get-ChildItem $PSScriptRoot/../model/
	$Selection = (Read-Host "Enter Index of Desired Character")
	Write-Information ("Entered Selection of {0}" -f $Selection)
	$character = Get-Content $authChar[$Selection] | ConvertFrom-Json
	return $character
}
