$headers = @{
    "Authorization" = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNsZGRyb2Rqb3VycHdqY3hybm9hIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NzAzNDczNywiZXhwIjoyMDkyNjEwNzM3fQ.-fOqlJ3Jh0iTUjG5qPmNA5Fz_qF5BHysaFY9aUEHU08"
    "apikey" = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNsZGRyb2Rqb3VycHdqY3hybm9hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcwMzQ3MzcsImV4cCI6MjA5MjYxMDczN30.PatKKd5dnYIJ0eKYE-aNGpG5OAKt15mNG3HbAti3cPc"
}

Write-Host "Fetching system_config..."
$response = Invoke-RestMethod -Uri "https://slddrodjourpwjcxrnoa.supabase.co/rest/v1/system_config?select=*" -Method Get -Headers $headers
$response | ConvertTo-Json -Depth 5

Write-Host ""
Write-Host "Fetching system_profit_snapshots (first 3)..."
$snapshots = Invoke-RestMethod -Uri "https://slddrodjourpwjcxrnoa.supabase.co/rest/v1/system_profit_snapshots?select=*&limit=3&order=date_key.asc" -Method Get -Headers $headers
$snapshots | ConvertTo-Json -Depth 5

Write-Host ""
Write-Host "Fetching investors..."
$investors = Invoke-RestMethod -Uri "https://slddrodjourpwjcxrnoa.supabase.co/rest/v1/investors?select=*" -Method Get -Headers $headers
$investors | ConvertTo-Json -Depth 5
