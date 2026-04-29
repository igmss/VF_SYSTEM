$body = @{
    startDate = "2026-03-18"
    endDate = "2026-04-27"
    resetPaidFlags = $true
} | ConvertTo-Json

$headers = @{
    "Authorization" = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNsZGRyb2Rqb3VycHdqY3hybm9hIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NzAzNDczNywiZXhwIjoyMDkyNjEwNzM3fQ.-fOqlJ3Jh0iTUjG5qPmNA5Fz_qF5BHysaFY9aUEHU08"
    "Content-Type" = "application/json"
}

Write-Host "Rebuilding profit snapshots with corrected openingCapital (180000)..."
$response = Invoke-RestMethod -Uri "https://slddrodjourpwjcxrnoa.supabase.co/functions/v1/rebuild-profit-snapshots" -Method Post -Headers $headers -Body $body
Write-Host "Rebuild Response:"
$response | ConvertTo-Json -Depth 5

Write-Host ""
Write-Host "Testing get-investor-performance..."
$invResponse = Invoke-RestMethod -Uri "https://slddrodjourpwjcxrnoa.supabase.co/functions/v1/get-investor-performance" -Method Post -Headers $headers -Body "{}"
Write-Host "Investor Response:"
$invResponse | ConvertTo-Json -Depth 10

Write-Host ""
Write-Host "Testing get-partner-performance..."
$partResponse = Invoke-RestMethod -Uri "https://slddrodjourpwjcxrnoa.supabase.co/functions/v1/get-partner-performance" -Method Post -Headers $headers -Body "{}"
Write-Host "Partner Response:"
$partResponse | ConvertTo-Json -Depth 10
