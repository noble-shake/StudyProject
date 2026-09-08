# build_bundle.ps1
# index.html 에 어떤 폴더의 md 문서든 내장한 단일 파일 DOCS_BUNDLE.html 을 생성합니다.
# 엔진(index.html·mermaid.min.js·이 스크립트)은 이 저장소 전체가 공유합니다 — 특정 엔진/프로젝트에
# 종속되지 않습니다. 각 문서 폴더는 이 스크립트를 가리키는 짧은 build_bundle.cmd 런처만 둡니다.
#
# 실행 방법
#   1) 문서 폴더의 build_bundle.cmd 를 더블클릭 (가장 쉬움. 창이 닫히지 않습니다)
#   2) powershell -NoProfile -ExecutionPolicy Bypass -File VIEWER\build_bundle.ps1 -Root "Unity" -Title "Unity Docs"
#
# 옵션
#   -Root      번들에 담을 md 문서들의 루트 폴더. 생략하면 현재 작업 디렉터리.
#   -Output    결과 HTML 경로. 생략하면 "<Root>\DOCS_BUNDLE.html".
#   -Title     뷰어 제목(브라우저 탭 + 사이드바 제목). 생략하면 기본값("Dev Docs Viewer") 유지.
#   -Subtitle  사이드바 부제. 생략하면 기본값 유지.
#   -NoPause   끝에서 멈추지 않습니다.

[CmdletBinding()]
param(
    [string]$Root,
    [string]$Output,
    [string]$Title,
    [string]$Subtitle,
    [switch]$NoPause
)

$exitCode = 0

function Get-RelativePath([string]$fromDir, [string]$toFile)
{
    $fromUri = New-Object System.Uri(($fromDir.TrimEnd('\') + '\'))
    $toUri   = New-Object System.Uri($toFile)
    $rel     = $fromUri.MakeRelativeUri($toUri).ToString()
    return [Uri]::UnescapeDataString($rel)
}

try
{
    $viewerDir = $PSScriptRoot
    $template  = Join-Path $viewerDir 'index.html'
    $mermaid   = Join-Path $viewerDir 'mermaid.min.js'

    if (-not $Root) { $Root = (Get-Location).Path }
    if (-not (Test-Path $Root))
    {
        Write-Host ('Root 폴더를 찾을 수 없습니다: ' + $Root) -ForegroundColor Red
        exit 2
    }
    $Root = (Resolve-Path $Root).Path

    if (-not $Output) { $Output = Join-Path $Root 'DOCS_BUNDLE.html' }
    $outDir = Split-Path -Parent $Output
    if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

    Write-Host 'build_bundle - md 문서를 단일 HTML 로 묶습니다' -ForegroundColor White
    Write-Host ('문서 루트: ' + $Root)
    Write-Host ('출력: ' + $Output)

    if (-not (Test-Path $template))
    {
        Write-Host ('엔진 템플릿을 찾을 수 없습니다: ' + $template) -ForegroundColor Red
        exit 2
    }

    # VIEWER 폴더 자체와 .git 은 제외. README 를 맨 앞에 둔다.
    $files = @(Get-ChildItem -Path $Root -Recurse -Filter *.md -File |
               Where-Object { $_.FullName -notmatch '\\VIEWER\\' -and $_.FullName -notmatch '\\\.git\\' } |
               Sort-Object @{ Expression = { if ($_.Name -match 'README') { 0 } else { 1 } } }, FullName)

    if ($files.Count -eq 0)
    {
        Write-Host ('내장할 md 파일이 없습니다: ' + $Root) -ForegroundColor Red
        exit 2
    }

    $sb = New-Object System.Text.StringBuilder

    foreach ($f in $files)
    {
        $rel  = $f.FullName.Substring($Root.Length).TrimStart([char]0x5C).Replace([char]0x5C, '/')
        $text = Get-Content -Path $f.FullName -Raw -Encoding UTF8

        # </script 만 이스케이프하면 script 블록이 조기 종료되지 않는다
        $text = $text -replace '</script', '<\/script'

        [void]$sb.AppendLine('<script type="text/markdown" data-name="' + $rel + '">')
        [void]$sb.AppendLine($text)
        [void]$sb.AppendLine('</script>')

        Write-Host ('  + ' + $rel) -ForegroundColor DarkGray
    }

    $html  = Get-Content -Path $template -Raw -Encoding UTF8
    $start = '<!--DOCS_EMBED_START-->'
    $end   = '<!--DOCS_EMBED_END-->'

    if (($html -notlike ('*' + $start + '*')) -or ($html -notlike ('*' + $end + '*')))
    {
        Write-Host ('index.html 에 임베드 마커가 없습니다: ' + $start + ' / ' + $end) -ForegroundColor Red
        exit 2
    }

    $pattern = [regex]::Escape($start) + '[\s\S]*?' + [regex]::Escape($end)
    $replace = $start + "`n" + $sb.ToString() + $end
    $html = [regex]::Replace($html, $pattern, { $replace })

    if ($Title)
    {
        $html = $html -replace '<title>[^<]*</title>', ('<title>' + $Title + '</title>')
        $html = $html -replace '<h1>Dev Docs Viewer</h1>', ('<h1>' + $Title + '</h1>')
    }
    if ($Subtitle)
    {
        $html = $html -replace '<p class="sub">[^<]*</p>', ('<p class="sub">' + $Subtitle + '</p>')
    }

    # mermaid.min.js 는 폴더마다 복사하지 않고, 출력 위치에서 저장소 루트 VIEWER/mermaid.min.js 로의
    # 상대경로를 계산해 넣는다 (엔진을 한 곳에서만 유지하기 위함).
    if (Test-Path $mermaid)
    {
        $relMermaid = Get-RelativePath $outDir $mermaid
        $html = $html -replace 'src="mermaid\.min\.js"', ('src="' + $relMermaid + '"')
    }

    # BOM 없는 UTF-8 로 저장 (브라우저가 meta charset 으로 읽는다)
    [System.IO.File]::WriteAllText($Output, $html, (New-Object System.Text.UTF8Encoding($false)))

    Write-Host ''
    Write-Host ('생성 완료: ' + $Output) -ForegroundColor Green
    Write-Host ('문서 ' + $files.Count + '개 내장. 더블클릭으로 열립니다.')
}
catch
{
    Write-Host ''
    Write-Host '실행 중 오류가 발생했습니다:' -ForegroundColor Red
    Write-Host ('  ' + $_.Exception.Message) -ForegroundColor Red
    if ($_.InvocationInfo) { Write-Host ('  위치: ' + $_.InvocationInfo.PositionMessage) -ForegroundColor DarkGray }
    $exitCode = 2
}
finally
{
    if (-not $NoPause)
    {
        Write-Host ''
        Write-Host '창을 닫으려면 Enter 를 누르세요.' -ForegroundColor DarkGray
        try { Read-Host | Out-Null } catch { }
    }
}

exit $exitCode
