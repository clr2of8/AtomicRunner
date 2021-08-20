$PathToAtomicsFolder = $( 
    if ($IsLinux -or $IsMacOS) { 
        $HOME + "/AtomicRedTeam/invoke-atomicredteam" 
    } 
    else { 
        $env:HOMEDRIVE + "\AtomicRedTeam\invoke-atomicredteam" 
    }
)
Import-Module $(Join-Path $PathToAtomicsFolder "Invoke-AtomicRedTeam.psd1") -Force

$testing = $false
if ($testing) {
    Import-Module $(Join-Path $pwd "Invoke-AtomicRunner.ps1") -Force
    Invoke-AtomicRunner -ShowDetails -Testing
}
else {
    $runnerScript = "C:\Users\art\AtomicRunner\Invoke-AtomicRunner.ps1"
    $outputFile = "C:\Users\art\AtomicRunner\all-out.txt"
    if ($IsLinux -or $IsMacOS) {
        $runnerScript = "/Users/art/AtomicRunner/Invoke-AtomicRunner.ps1"
        $outputFile = "/Users/art/AtomicRunner/all-out.txt" 
    }

    Import-Module $runnerScript -Force
    # log all execution output to a file for debugging
    Invoke-AtomicRunner *>>  $outputFile

}
