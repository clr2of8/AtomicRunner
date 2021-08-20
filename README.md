# AtomicRunner

This repository contains scripts to help you run a configurable list of atomic tests unattended in a way that aids detection development. The script is to designed to run all the tests you have listed in the CSV schedule once per week by default. Before if runs each atomic it appends the atomic test GUID to the end of the hostname. This makes it easier to determine which detections fired from which atomics because the hostname in the detection will include the GUID of the atomic test that was running at the time. The cleanup commands are run after atomic test execution as well.

This script works for Windows, Linux and MacOS. You need to have PowerShell Core installed on Linux/MacOS to use these scripts

## Overall Architecture

A CSV file containing atomic technique numbers and GUIDS (aka "the schedule"), defines which tests should be run and in which order. It can also be used to define custom input arguments for the test.

A scheduled task/cronjob is used to call the Kickoff-AtomicRunner.ps1 script, which in turn calls the Invoke-AtomicRunner.ps1 script which reads the schedule and executes the test. The Invoke-AtomicRunner script performs the following:

* If the schedule file doesn't exist, create one by reading in all of the atomics from the Atomic Red Team default install directory and adding them to the list.
* If the `-RefreshSchedule` flag is included in the call to the script, add any new atomics to the schedule that aren't already there.
* Disable Windows Defender Realtime monitoring allowing all tests to run
* If any flags like `-Cleanup` or `-GetPrereqs` are found, just perform that task (cleanup, getpreqs ...) for all atomics on the schedule and exit
* Read GUID from the hostname of the computer, e.g. `basehostname-0be2230c-9ab3-4ac2-8826-3199b9a0ebf8` and execute that atomic test (by GUID)
* Wait a calculated amount of times such that all atomics on the schedule run once per week and then run the cleanup commands for the atomic
* Determine the GUID for the next test to be run from the next item in the schedule, rename the host to include the next test GUID and restart the computer such that the hostname update is fully implemented.
* Repeat


## Initial Setup

Update the paths in the scripts to match your configuration. The scripts script assumes that Atomic Red Team is installed to the default directory and that these runner scripts are at C:\Users\art\AtomicRunner or /Users/art/AtomicRunner.

## Create the initial schedule

An example schedule is provided in this repo (AtomicRunnerSchedule.csv) but it only has two tests listed. If you want a full schedule you can delete this file and create a full schdule as follows.

Import the Invoke-AtomicRunner script, and call the Get-NewSchedule function.

```powershell
Get-NewSchedule("C:\AtomicRedTeam\atomics")
```

Now configure the AtomicRunnerSchedule.csv file by marking the ones you want to run as active (TRUE) or disabled (FALSE). You can also add input arguments and notes as to why you are or are not including certain atomic tests.

## Admin Credentials (Windows Only)

Credentials for a user in the adminstrators group is required to rename the host. These credentials need to be provided in encrypted form in the same directory as these scripts in a file called `psc.txt`. You can create such a file with the following command:

```powershell
$credFile = "C:\Users\art\AtomicRunner\psc.txt"
(Get-Credential).Password | ConvertFrom-SecureString | Out-File $credFile
```

### The scheduled task/cronjob

On Windows, you can create the scheduled task that keeps the process going through a reboot as follows:

```
schtasks /create /tn "KickOff-AtomicRunner" /tr "powershell.exe -exec bypass -file c:\users\art\AtomicRunner\KickOff-AtomicRunner.ps1" /sc onstart /delay 0001:00 /RU "testlab\AtomicRunner" /RP *
```

Replace `testlab\AtomicRunner` with your own AD domain name and administrative user name and update the file paths as necessary

On Linux, you can create the cronjob that keeps the process going through a reboot as follows:

```
@reboot root /bin/pwsh -Command /Users/art/AtomicRunner/Kickoff-AtomicRunner.ps1
```

## Other Notes

### Stopping the automation

You can temporily disable the script automation by placing a file called `stop.txt` in the script directory. This is handy to keep the computer from restarting on you all the time during maintenance. To re-enable the automation, remove the stop file and restart the computer.

## Logging

All the output from the atomics and the runner automation can be found in the scripts directory in a file called `all-out.txt`. Output from the Invoke-AtomicRunner script itself (not the atomics) is found in `log.txt`