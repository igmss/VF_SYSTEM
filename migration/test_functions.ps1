$body = @{
} | ConvertTo-Json

$headers = @{
    "Authorization" = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNsZGRyb2Rqb3VycHdqY3hybm9hIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NzAzNDczNywiZXhwIjoyMDkyNjEwNzM3fQ.-fOqlJ3Jh0iTUjG5qPmNA5Fz_qF5BHysaFY9aUEHU08"
    "Content-Type" = "application/json"
}

Write-Host "Testing get-investor-performance..."
$response = Invoke-RestMethod -Uri "https://slddrodjourpwjcxrnoa.supabase.co/functions/v1/get-investor-performance" -Method Post -Headers $headers -Body $body
Write-Host "Investor Response:"
$response | ConvertTo-Json -Depth 10

Write-Host ""
Write-Host "Testing get-partner-performance..."
$response2 = Invoke-RestMethod -Uri "https://slddrodjourpwjcxrnoa.supabase.co/functions/v1/get-partner-performance" -Method Post -Headers $headers -Body $body
Write-Host "Partner Response:"
$response2 | ConvertTo-Json -Depth 10
