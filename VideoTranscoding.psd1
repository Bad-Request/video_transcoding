@{
    RootModule        = 'VideoTranscoding.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b7c4e2f1-9a3d-4e58-8c16-2d7f5a9e4b03'
    Author            = 'Bad-Request'
    Copyright         = 'Copyright (c) 2026. MIT licensed.'
    Description       = 'Shared plumbing for the video transcoding tools: media scanning, stream selection, native tool invocation and prerequisite checking.'

    # 7.4 is the LTS floor. Not Windows PowerShell 5.1: it lacks ?? and
    # ternaries, cannot do ConvertFrom-Json -AsHashtable, and has the broken
    # native-argument quoting that this port exists to stop working around.
    PowerShellVersion = '7.4'

    FunctionsToExport = @(
        'Get-MediaInfo'
        'Select-MediaStream'
        'Get-StreamTag'
        'Get-StreamDisposition'
        'Format-CommandLine'
        'Format-Elapsed'
        'Invoke-NativeTool'
        'Test-Prerequisite'
        'Get-VersionText'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('video', 'transcoding', 'handbrake', 'ffmpeg')
            LicenseUri = 'https://github.com/Bad-Request/video_transcoding/blob/master/LICENSE'
            ProjectUri = 'https://github.com/Bad-Request/video_transcoding'
        }
    }
}
