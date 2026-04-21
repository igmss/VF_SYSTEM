$API_KEY = ""
$PROJECT_ROOT = "D:\New folder\vodafone_system"
$FILES = @(
    "lib\models\investor.dart",
    "lib\models\investor_profit_snapshot.dart",
    "lib\models\partner.dart",
    "lib\models\partner_profit_snapshot.dart",
    "lib\models\system_profit_snapshot.dart",
    "lib\providers\distribution_provider.dart",
    "lib\screens\admin\investors_screen.dart",
    "lib\screens\admin\investor_detail_screen.dart",
    "lib\screens\admin\partners_screen.dart"
)

foreach ($file in $FILES) {
    $filePath = Join-Path $PROJECT_ROOT $file
    Write-Host "Uploading ${file}..."
    if (Test-Path $filePath) {
        $response = curl.exe -X POST "https://api.anthropic.com/v1/files" `
             -H "x-api-key: $API_KEY" `
             -H "anthropic-version: 2023-06-01" `
             -H "anthropic-beta: files-api-2025-04-14" `
             -F "file=@$filePath"
        Write-Host "Response for ${file}: $response"
    } else {
        Write-Warning "File not found: $filePath"
    }
}
