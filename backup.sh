#!/bin/bash


### Text formatting presets
normal="\e[0m"
bold="\e[1m"
default="\e[39m"
red="\e[31m"
green="\e[32m"
yellow="\e[93m"
magenta="\e[35m"
cyan="\e[96m"
stamp="[`date +%Y-%m-%d` `date +%H:%M:%S`]"


### Functions ###

### scriptHelp -- display usage information for this script
function scriptHelp {
    echo "In the future, I will be something helpful!"
    # exit with code 1 -- there is no use logging this
    exit 1
}

### quit -- exit the script after logging any errors, warnings, etc.
function quit {
    # list generated warnings, if any
    if [ ${#exitWarn[@]} -gt 0 ]; then
        echo -e "${bold}${yellow}Script generated the following" \
            "warnings:${normal}" >> "$logFile"
        for warn in "${exitWarn[@]}"; do
            echo -e "${yellow}-- [WARNING] ${warningExplain[$warn]}" \
                "(code: ${warn}) --${normal}" >> "$logFile"
        done
    fi
    if [ -z "$1" ]; then
        # exit cleanly
        echo -e "${bold}${magenta}${stamp} -- Script completed" \
            "--$normal" >> "$logFile"
        exit 0
    else
        # log error code and exit with said code
        echo -e "${bold}${red}${stamp} -- [ERROR] ${errorExplain[$1]}" \
            "(code: $1) --$normal" >> "$logFile"
        exit "$1"
    fi
}

function checkExist {
    if [ "$1" = "ff" ]; then
        # find file
        if [ -e "$2" ]; then
            # found
            return 0
        else
            # not found
            return 1
        fi
    elif [ "$1" = "fd" ]; then
        # find directory
        if [ -d "$2" ]; then
            # found
            return 0
        else
            # not found
            return 1
        fi
    fi
}

### ncMaint - perform NextCloud maintenance mode entry and exit
function ncMaint {
    if [ "$1" = "on" ]; then
        echo -e "${bold}${cyan}${stamp}Putting NextCloud in maintenance" \
            "mode..." >> "$logFile"
        su -c "php ${ncRoot}/occ maintenance:mode --on" - ${webUser} \
            >> "$logFile" 2>&1
        maintResult="$?"
        return "$maintResult"
    elif [ "$1" = "off" ]; then
        echo -e "${bold}${cyan}${stamp}Exiting NextCloud maintenance mode..." \
            >> "$logFile"
        su -c "php ${ncRoot}/occ maintenance:mode --off" - ${webUser} \
            >> "$logFile" 2>&1
        maintResult="$?"
        return "$maintResult"
    fi
}

### cleanup - cleanup files and directories created by this script
function cleanup {
    ## remove SQL dump file and directory
    rm -rf "$sqlDumpDir" >> "$logFile" 2>&1
    # verify directory is gone
    checkExist fd "$sqlDumpDir"
    checkResult="$?"
    if [ "$checkResult" = "0" ]; then
        # directory still exists
        exitWarn+=('111')
    else
        # directory removed
        echo -e "${bold}${cyan}${stamp} Removed SQL temp directory${normal}" \
            >> "$logFile"
    fi

    ## remove 503 error page
    # check if 503 page was specified to begin with
    if [ -n "$err503File" ]; then
        # proceed with cleanup
        rm -f "$webroot/$err503File" >> "$logFile" 2>&1
        # verify file is actually gone
        checkExist ff "$webroot/$err503File"
        checkResult="$?"
        if [ "$checkResult" = "0" ]; then
            # file still exists
            exitWarn+=('5030')
        else
            # file removed
            echo -e "${bold}${cyan}${stamp} Removed 503 error page" \
                "from webroot${normal}" >> "$logFile"
        fi
    fi
}

### End of Functions ###


### Default parameters

# store the logfile in the same directory as this script using the script's name
# with the extension .log
scriptPath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
scriptName="$( basename ${0} )"
logFile="$scriptPath/${scriptName%.*}.log"

# set script parameters to null and initialize array variables
unset PARAMS
unset borgCreateParams
unset borgPruneParams
unset sqlDumpDir
unset err503File
unset webroot
errorExplain=()
exitWarn=()
warningExplain=()


### Error codes
errorExplain[100]="Could not put NextCloud into Maintenance mode."

### Warning codes & messages
warningExplain[111]="Could not remove SQL dump file and directory.  Please remove manually."
warningExplain[5030]="Could not remove 503 error page. This MUST be removed manually before NGINX will serve webclients!"
warningExplain[5031]="Name of a 503 error page file was not specified (-5 parameter missing)"
warningExplain[5032]="The specified 503 error page could not be found"
warningExplain[5033]="No webroot path was specified (-r parameter missing)"
warningExplain[5034]="The specified webroot could not be found"
warningExplain[5035]="Error copying 503 error page to webroot"
warn503="   ${ltYellow}Web users will NOT be informed the server is down!${normal}"

### Process script parameters

# if no parameters provided, then show the help page and exit with error
if [ -z $1 ]; then
    # show script help page
    scriptHelp
fi

# use GetOpts to process parameters
while getopts ':l:nv5:r:' PARAMS; do
    case "$PARAMS" in
        l)
            # use provided location for logFile
            logFile="${OPTARG}"
            ;;
        n)
            # normal output from Borg
            borgCreateParams='--stats'
            borgPruneParams='--list'
            ;;
        v)
            # verbose output from Borg
            borgCreateParams='--list --stats'
            borgPruneParams='--list'
            ;;
        5)
            # 503 error page name
            err503File="${OPTARG}"
            ;;
        r)
            # path to webroot for NextCloud installation
            webroot="${OPTARG}"
            ;;
        ?)
            # unrecognized parameters trigger scriptHelp
            scriptHelp
            ;;
    esac
done


### Verify script running as root, otherwise display error on console and exit
if [ $(id -u) -ne 0 ]; then
    echo -e "${red}This script MUST be run as ROOT. Exiting.${normal}"
    exit 2
fi


### Log start of script operations
echo -e "${bold}${magenta}${stamp}-- Start $scriptName execution ---" >> "$logFile"


### Export logFile variable for use by Borg
export logFile="$logFile"


### Create sqlDump temporary directory and sqlDumpFile name
sqlDumpDir=$( mktemp -d )
sqlDumpFile="backup-`date +%Y%m%d_%H%M%S`.sql"
echo -e "${normal}${stamp} mySQL dump file will be stored at:" >> "$logFile"
echo -e "${ltYellow}${sqlDumpDir}/${sqlDumpFile}${normal}" >> "$logFile"


### 503 error page

# Verify 503 existance
if [ -z "$err503File" ]; then
    # no 503 file has been provided
    echo -e "$warn503" >> "$logFile"
    exitWarn+=('5031')
else
    checkExist ff "$err503File"
    checkResult="$?"
    if [ "$checkResult" = "1" ]; then
        # 503 file specified could not be found
        echo -e "$warn503" >> "$logFile"
        exitWarn+=('5032')
    else
        # 503 file found
        # verify webroot exists
        if [ -z "$webroot" ]; then
            # no webroot path provided
            echo -e "$warn503" >> "$logFile"
            exitWarn+=('5033')
        else
            # verify provided webroot path exists
            checkExist fd "$webroot"
            checkResult="$?"
            if [ "$checkResult" = "1" ]; then
                # webroot directory specified could not be found
                echo -e "$warn503" >> "$logFile"
                exitWarn+=('5034')
            else
                # webroot exists and 503 exists, copy 503 to webroot
                cp "${err503File}" "$webroot/" >> "$logFile" 2>&1
                copyResult="$?"
                # verify copy was successful
                    if [ "$copyResult" = "1" ]; then
                        # copy was unsuccessful
                        echo -e "$warn503" >> "$logFile"
                        exitWarn+=('5035')
                    else
                        # copy was successful
                        echo -e "${bold}${cyan}${stamp} 503 error page" \
                            "copied to webroot${normal}" >> "$logFile"
                    fi
            fi
        fi
    fi
fi


### Put NextCloud in maintenance mode
#ncMaint on
# check if successful
#if [ "$maintResult" = "0" ]; then
#    echo -e "${bold}${cyan}${stamp}...done${normal}" >> "$logFile"
#else
#    cleanup 503
#    quit 100
#fi

### Exit script
cleanup
quit

# This code should not be executed since the 'quit' function should terminate
# this script.  Therefore, exit with code 99 if we get to this point.
exit 99
