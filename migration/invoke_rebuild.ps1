$body = @{
    startDate = "2026-03-18"
    endDate = "2026-04-29"
    resetPaidFlags = $true
} | ConvertTo-Json

$headers = @{
    "Authorization" = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNsZGRyb2Rqb3VycHdqY3hybm9hIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NzAzNDczNywiZXhwIjoyMDkyNjEwNzM3fQ.-fOqlJ3Jh0iTUjG5qPmNA5Fz_qF5BHysaFY9aUEHU08"
    "Content-Type" = "application/json"
}

$response = Invoke-RestMethod -Uri "https://slddrodjourpwjcxrnoa.supabase.co/functions/v1/rebuild-profit-snapshots" -Method Post -Headers $headers -Body $body

Write-Host "Response:"
$response | ConvertTo-Json -Depth 10
