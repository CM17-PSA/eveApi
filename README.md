# PowerShell integration for Eve API.

This ia a fairly basic state for the Eve.API integration definitions. This now handles the ability to colelct, and generate your authentication token(s) as needed and managed per character with some baseline capabilities to complete followup actions from there after the authentication is completed. Please be aware that contents of the model directory in local environments will be populated with some secure data and the like.

As work progresses through the development of this project I will be adjusting the means in which this data is stored so as to help not keep so much detail in plaintext moving forward. You will likely notice a similar issue within the main.ps1 of the project as it contains lines that will need to be populated by the user with the appropriate clientId and ClientSecret from ESI to make use of the subsequent operations.

## Overview
