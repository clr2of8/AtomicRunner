# Authors: Carrie Roberts twitter:@OrOneEqualsOne GitHub:clr2of8
#          Daniel White GitHub: dwhite9
#          Laken Harrell GitHub:Andras32
# GitHub Repository: https://github.com/clr2of8/AtomicRunner
function Invoke-AtomicRunner {
    [CmdletBinding(
        SupportsShouldProcess = $true,
        PositionalBinding = $false,
        ConfirmImpact = 'Medium')]
    Param(
        [Parameter(Mandatory = $false)]
        [switch]
        $ShowDetails,

        [Parameter(Mandatory = $false)]
        [switch]
        $CheckPrereqs,

        [Parameter(Mandatory = $false)]
        [switch]
        $GetPrereqs,

        [Parameter(Mandatory = $false)]
        [switch]
        $Cleanup,

        [Parameter(Mandatory = $false)]
        [switch]
        $ShowDetailsBrief,

        [Parameter(Mandatory = $false)]
        [String[]]
        $TestGuids,

        [Parameter(Mandatory = $false)]
        [switch]
        $Testing,

        [Parameter(Mandatory = $false)]
        [switch]
        $RefreshSchedule,

        [Parameter(Mandatory = $false)]
        [String]
        $PathToAtomicsFolder = $( if ($IsLinux -or $IsMacOS) { $Env:HOME + "/AtomicRedTeam/atomics" } else { $env:HOMEDRIVE + "\AtomicRedTeam\atomics" }),

        [Parameter(Mandatory = $false)]
        [String]
        $OS = $( if ($IsLinux) { "linux" } elseif ($IsMacOS) { "macos" } else { "windows" }),

        [Parameter(Mandatory = $false)]
        [String]
        $basePath = $( 
            if ($IsLinux -or $IsMacOS) { 
                if ($Testing) { $pwd } else { "/Users/art/artexecutionlogs$" }
            } 
            else {
                if ($Testing) { $pwd } else { "C:\Users\art\artexecutionlogs$" }
            }
        ),

        [Parameter(Mandatory = $false)]
        [String]
        $user = $(if ($Testing) { $env:USERNAME } else { "testlab\AtomicRunner" }),

        [Parameter(Mandatory = $false)]
        [String]
        $basehostname = $((hostname).split("-")[0])
    )
    Begin { }
    Process {       
        function Log ($message) {
            $now = "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
            Write-Host -fore cyan $message
            Add-Content $logFile "$now`: $message"
        }

        function Get-GuidFromHostName($BaseHostname) {
            $guid = [System.Net.Dns]::GetHostName() -replace $($BaseHostname + "-"), ""

            if (!$guid) {
                Log "Hostname has not been updated or could not parse out the Guid: " + $guid
                return
            }
            
            # Confirm hostname contains a guid
            [regex]$guidRegex = '(?im)^[{(]?[0-9A-F]{8}[-]?(?:[0-9A-F]{4}[-]?){3}[0-9A-F]{12}[)}]?$'

            if ($guid -match $guidRegex) { return $guid } else { return "" }
        }

        function Convert-StringtoHT ($htstring) {
            $pattern = '@\{[ ]*\"(?<Key>.*?)\"[ ]*=[ ]*\"(?<Value>.*?)\"[ ]*}'
            $hashTable = @{ }
            foreach ($match in [regex]::Matches($htstring, $pattern)) {
                $hashTable[$match.Groups['Key'].Value] = $match.Groups['Value'].Value
            }
            $hashTable
        }

        function Invoke-AtomicTestFromScheduleRow ($tr, $psb) {
            if ($tr.InputArgs -eq '') {
                $tr.InputArgs = @{ }
            }
            else {
                $tr.InputArgs = Convert-StringtoHT($tr.InputArgs)
            }

            if ($RefreshSchedule.IsPresent) {
                $psb.Remove('RefreshSchedule') | Out-Null
            }
            If ($Testing.IsPresent) {
                $psb.Remove('Testing') | Out-Null
            }

            #Run the Test
            Invoke-AtomicTest $tr.Technique -TestGuids $tr.auto_generated_guid -InputArgs $tr.InputArgs -TimeoutSeconds $tr.TimeoutSeconds -ExecutionLogPath $execLogPath -PathToAtomicsFolder $PathToAtomicsFolder @psb
        }

        function Rename-ThisComputer ($tr, $BaseHostname) {
            $hash = $tr.auto_generated_guid

            $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, (Get-Content $credFile | ConvertTo-SecureString)
            $newHostName = "$BaseHostname-$hash"
            Log "Setting hostname to $newHostName"

            If (Test-Path $stopFile) {
                Log "exiting script because because $stopFile exists"
                exit
            }

            if ($IsLinux) {
                iex $("hostnamectl set-hostname $newHostName")
                iex $("shutdown -r now")
            }
            else {
                if ($Testing) {
                    Rename-Computer -NewName $newHostName -Force -LocalCredential $cred -Restart
                }
                else {
                    Rename-Computer -NewName $newHostName -Force -DomainCredential $cred -Restart
                }
                Start-Sleep -seconds 30
                Log "uh oh, still haven't restarted - should never get to here"
                exit
            }
            
        }
        
        # based on the number of tests in our AtomicRunnerSchedule.csv, determine how often to run tests so that they each end up running once per week.
        function Get-TimingVariable ($sched) {
            $atcount = $sched.Count
            if ($null -eq $atcount) { $atcount = 1 }
            $weeklyminutes = 10080
            $sleeptime = ($weeklyminutes / $atcount) #in minutes
            if ($sleeptime -gt 90) {
                $sleeptime = 90
            }
            return $sleeptime
        }

        function Get-NewSchedule($PathToAtomicsFolder) {
            $AllAtomicTests = New-Object System.Collections.ArrayList

            # Loop through all atomic yaml files to load into list of objects
            Get-ChildItem $PathToAtomicsFolder -Recurse -Filter *.yaml -File | ForEach-Object {
                $currentTechnique = [System.IO.Path]::GetFileNameWithoutExtension($_.FullName)
                if ( $currentTechnique -ne "index" ) { 
                    $technique = Get-AtomicTechnique -Path $_.FullName
                    if ($technique) {                                
                        $technique.atomic_tests | ForEach-Object -Process {
                            $test = New-Object -TypeName psobject
                            $test | Add-Member -MemberType NoteProperty -Name Technique -Value ($technique.attack_technique -join "|")
                            $test | Add-Member -MemberType NoteProperty -Name TestName -Value $_.name
                            $test | Add-Member -MemberType NoteProperty -Name auto_generated_guid -Value $_.auto_generated_guid
                            $test | Add-Member -MemberType NoteProperty -Name supported_platforms -Value ($_.supported_platforms -join "|")
                            $test | Add-Member -MemberType NoteProperty -Name TimeoutSeconds -Value 120
                            $test | Add-Member -MemberType NoteProperty -Name InputArgs -Value ""
                            $test | Add-Member -MemberType NoteProperty -Name hostname -Value ""
                            $test | Add-Member -MemberType NoteProperty -Name active -Value $false
                            $test | Add-Member -MemberType NoteProperty -Name notes -Value ""
                            $dummy = $AllAtomicTests.Add(($test))
                        }
                    }
                }
            }
            return $AllAtomicTests
        }

        function Get-ScheduleRefresh($schedule, $PathToAtomicsFolder) {
            $AllAtomicTests = Get-NewSchedule $PathToAtomicsFolder
            
            # Check if any tests haven't been added to schedule and add them
            $update = $false
            foreach ($guid in $AllAtomicTests | Select-Object -ExpandProperty auto_generated_guid) {
                $fresh = $AllAtomicTests | Where-Object { $_.auto_generated_guid -eq $guid }
                $old = $schedule | Where-Object { $_.auto_generated_guid -eq $guid }

                if (!$old) {
                    $update = $true
                    $schedule += $fresh
                }
            }
            if ($update) {
                $schedule | Export-Csv $scheduleFile
                Log "Schedule has been updated with new tests."
            }
            return $schedule

        }


        # path and filename variables
        $runner = Join-Path $basePath "AtomicRunner"
        $scheduleFile = Join-Path $runner "AtomicRunnerSchedule.csv"
        $timeLocal = (Get-Date(get-date) -uformat "%Y-%m-%d").ToString()
        $execLogPath = Join-Path $basePath "$timeLocal`_$BaseHostName-ExecLog.csv"
        $stopFile = Join-Path $runner "stop.txt"
        $logFile = Join-Path $runner "log.txt"
        $credFile = Join-Path $runner "psc.txt" # Create this file with: (Get-Credential).Password | ConvertFrom-SecureString | Out-File $credFile

        # Read schedule file, if it doesn't exist pull from Atomics
        if (Test-Path($scheduleFile)) {
            $schedule = Import-Csv $scheduleFile
        }
        else {
            Log "Generating new schedule: $scheduleFile"
            $schedule = Get-NewSchedule $PathToAtomicsFolder
            $schedule | Export-Csv $scheduleFile -NoTypeInformation
        }
        
        # if we need to generate/update schedule based on new Atomics
        if ($RefreshSchedule) {
            $schedule = Get-ScheduleRefresh $schedule $PathToAtomicsFolder
        }

        # Filter schedule to either Active/Supported Platform or TestGuids List
        if ($TestGuids) {
            $schedule = $schedule | Where-Object {
                ($Null -ne $TestGuids -and $TestGuids -contains $_.auto_generated_guid)  
            }
        }
        else {
            $schedule = $schedule | Where-Object {
                ($_.active -eq $true -and ($_.supported_platforms -like "*" + $OS + "*" ))
            }
        }

        # If the schedule is empty, end process
        if (!$schedule) {
            Log "No test guid's or active tests."
            return
        }

        # timing variables
        $SleepTillCleanup = Get-TimingVariable $schedule; if ($Testing) { $SleepTillCleanup = 0.25 } # in minutes
		    
        if ((Get-MpPreference | Select-Object -ExpandProperty DisableRealtimeMonitoring) -eq $false) {
            Log "Disabling RealtimeMonitoring"
            Set-MpPreference -DisableRealtimeMonitoring $true
        }

        # exit if we can't find the schedule file or if file stop.txt is found in the same directory as the schedule
        If (Test-Path $stopFile) {
            Log "exiting script because $stopFile does exist"
            exit
        }

        # Perform cleanup, Showdetails or Prereq stuff for all scheduled items and then exit
        if ($Cleanup -or $ShowDetails -or $CheckPrereqs -or $ShowDetailsBrief -or $GetPrereqs) {
            $schedule | ForEach-Object {
                Invoke-AtomicTestFromScheduleRow $_ $PSBoundParameters
            }
            exit
        }
          
        $guid = Get-GuidFromHostName $BaseHostname
        if ([string]::IsNullOrWhiteSpace($guid)) {
            Log "Test Guid ($guid) was null, using next item in the schedule"
        }
        else {
            Log "Found Test: $guid specified in hostname"
            $tr = $schedule | Where-Object { $_.auto_generated_guid -eq $guid }

            if ($null -ne $tr) {
                Invoke-AtomicTestFromScheduleRow $tr $PSBoundParameters
                Write-Host -Fore cyan "Sleeping for $SleepTillCleanup minutes before cleaning up"; Start-Sleep -Seconds ($SleepTillCleanup * 60)
                
                # Cleanup after running test
                $PSBoundParameters.Add('Cleanup', $true)
                Invoke-AtomicTestFromScheduleRow $tr $PSBoundParameters
            }
            else {
                Log "Could not find Test: $guid in schedule. Please update schedule to run this test."
            }
        }

        # Load next scheduled test before renaming computer
        $currentIndex += $schedule.indexof($tr) + 1
        if ($currentIndex -ge ($schedule.count)) { $currentIndex = 0 }
        $tr = $schedule[$currentIndex]

        if ($null -eq $tr) { 
            Log "Could not determine the next row to execute from the schedule, Starting from 1st row"; 
            $tr = $schedule[0] 
        }

        #Rename Computer and Restart
        Rename-ThisComputer $tr $BaseHostname 
    }
}