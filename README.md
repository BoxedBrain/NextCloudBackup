# NextCloud Backup using borgbackup

This script automates backing up your NextCloud installation using borgbackup
and a remote ssh-capable storage system.  I suggest using rsync.net since they
have great speeds and a special pricing structure for borgbackup/attic users
([details here](https://www.rsync.net/products/attic.html)).

This script automates the following tasks:

- Optionally copies a 503 error page to your webserver so users know when your
  server is unavailable due to backups being performed. The 503 file is removed
  when the backup is completed so users can login again
- Dumps mySQL database and adds it to the backup
- Handles entering and exiting NextCloud's maintenance mode to 'lock' accounts
  so changes are not made during the backup process
- Allows you to specify additional files you want backed up
- Allows you to specify files/directories to exclude from your backups (e.g.
  previews)
- Runs 'borg prune' to make sure you are trimming old backups on your schedule
- Creates an clear, easy to parse log file so you can easily keep an eye on your
  backups and any errors/warnings

## Installation/copying

Once you've either cloned this git or downloaded the release file, simply copy
the *'NCscripts'* folder to wherever you like.  I suggest putting it in your
*'/root'* directory since the root user must execute the script.  If you edit
the 503.html, nc_borg.details and nc_sql.details files in place, then you don't
have to specify their locations when running the script.

Remember to make the script executable!

    ```Bash
    chmod +x backup.sh
    ```

In addition, you can rename this script file to anything you like.  The log file
will use that same name by default when naming itself and any mention of this
file in the logs will automatically use whatever name you choose to give it.

## Environment notes

The script is designed to be easy to use but still be flexible enough to
accommodate a wide range of cn NextCloud setups.  I have tested it with
NextCloud 13 and 14 using a standard LEMP setup (Debian Stretch, NGINX, mariaDB
& PHP7).  The script accepts several parameters to provide it with the settings
it requires to function.  In addition, it reads external files for SQL and borg
settings, so you don't have to weed through the script code to supply things
like passwords.

## Why this script must be run as root

This script must be run by the root user and will exit with an error if you try
running it otherwise.  This is because NextCloud's OCC command (needed to put
NextCloud into maintenance mode) must be run as the web-user account and only
the root account can switch users without needing to stop and ask for
permission/passwords.

## Script parameters

You can run the script with the *'-?'* parameter to access the built-in help
which explains the parameters.  However, the following is more detailed
explanation of each parameter and how to use them.
**Note that any parameters needing a directory (webroot, nextcloud root, etc.)
can be entered with or without the trailing / since it's stripped by the script
anyways.**

General usage:

```Bash
/path/to/script/scriptname.sh -parameter argument -parameter argument ...
```

### Required parameters

#### -d _/path/to/data/_, NextCloud data directory

This is the full path to the location where NextCloud actually stores data.  In
a setup such as I recommend on my blog at
[https://mytechiethoughts.com](https://www.mytechiethoughts.com), you would be
using an entry such as *'/var/nc_data'*.  This directory and all subdirectories
automatically included in the backup.

#### -n _/path/to/nextcloud/_, NextCloud webroot

This is the directory in which NextCloud's php and html files are located.  It
is generally somewhere under your webroot directory.  This is required so the
script can find the 'OCC' command to invoke maintenance mode.

#### -w _accountName_, webuser account

This is the account that NextCloud runs under via your webserver.  This is
almost always *'www-data'*.  You would have to check your NGINX/Apache config to
be sure.  'OCC' will not run as any other user thus, the script cannot
enter/exit maintenance mode with knowing what user to emulate.

### Optional parameters

#### -5 _/path/to/filename.html_, path to 503 html error page

The path to an html file for the script to copy to your webroot during the
backup process.  This file can be scanned by your webserver and a 503 error can
be issued to users letting them know that your NextCloud is 'temporarily
unavailable' while being backed up.  A sample 503 page is included for you.

If you remove the default file or the one you specify is missing, a warning will
be issued by the script but, it will continue executing.  More details on the
503 notification can be found later in the [503 functionality](#503-functionality) section of this
document. **Default: _scriptpath/503.html_**

#### -b _/path/to/filename.file_, path to borg details file

This is a text file that lays out various borg options such as repo name,
password, additional files to include, exclusion patters, etc.  A sample file is
included for your reference.  More details, including the *required order* of
entries can be found later in this document in the [borg details file](#borg-details-file)
section.
**Default: _scriptpath/nc_borg.details_**

#### -l _/path/to/filename.file_, log file location

If you have a particular place you'd like this script to save it's log file,
then you can specify it using this parameter.  I would recommend *'/var/log'*.
By default, the script will name the log file *scriptname*.log and will save it
in the same directory as the script itself.
**Default: _scriptpath/scriptname.log_**

#### -s _/path/to/filename.file_, path to SQL details file

This is text file containing the details needed to connect to NextCloud's SQL
database.  For more information about the *required order* of entries can be
found later in this document in the [sql details file](#sql-details-file) section.
**Default: _scriptpath/nc_sql.details_**

#### -v, verbose output from borg

By default, the script will ask borg to generate summary only output and record
that in the script's log file.  If you are running the backup for the first time
or are troubleshooting, you may want a detailed output of all files and their
changed/unchanged/excluded status from borg.  In that case, specify the -v
switch.
**Note: This will make your log file very large, very quickly since EVERY file
being backed up is written to the log.**

#### -w _/path/to/webroot/_, path to webroot

This is the path to the directory your webserver is using as it's default root.
In other words, this is the directory that contains the html files served when
someone browses to your server.  Depending on your setup, this might be the same
as your NextCloud webroot.

This is used exclusively for 503 functionality since the script has to know
where to copy the 503 file.  If you don't want to use this functionality, you
can omit this parameter and the script will issue a warning and move on.  More
details can be found in the [503 functionality](#503-functionality) section later in this
document.

## Borg details file

This file contains all the data needed to access your borg remote data repo.
Each line must contain specific information in a specific order or needs to be
blank if that data is not required.  The sample file includes this data and
example entries.  The file must have the following information in the following
order:

    1. path to borg base directory **(required)**
    2. path to ssh private key for repo **(required)**
    3. connection string to remote repo **(required)**
    4. password for ssh key/repo **(required)**
    5. path to file listing additional files/directories to backup
    6. path to file containing borg-specific exclusion patterns
    7. purge timeframe options
    8. location of borg remote instance

### Protect your borg details file

This file contains information on how to access and decrypt your borg repo,
therefore, you **must** protect it.  You should lock it out to your root user.
Putting it in your root folder is not enough!  Run the following commands to
restrict access to the root user only (assuming filename is *'nc_borg.details'*):

```Bash
# make root the owner
chown root:root nc_borg.details
# restrict access to root only
chmod 600 nc_borg.details
```

### borg specific entries (lines 1-4)

If you need help with these options, then you should consult the borg
documentation or search my blog at
[https://mytechiethoughts.com](https://mytechiethoughts.com) for borg.

### additional files/directories to backup

This points to a plain-text file listing additional files and directories you'd
like borg to include in the backup.  The sample file, *'xtraLocations.borg'*
contains the most likely files you'd want to include assuming you're using a
standard setup like it outline in my blog.

The following would include all files in the home folder for users *'foo'* and
*'bar'* and any conf files in *'/etc/someProgram'*:

```Bash
/home/foo/
/home/bar/
/etc/someProgram/*.conf
```

You can leave this line blank to tell borg to only backup your NextCloud data
directory and the SQL dump.  However, this is pretty unusual since you would not
be including any configuration files, webserver configurations, etc.  If you
omit this line, the script will log a warning in your log.

### exclusion patterns

This points to a plain-text file containing borg-specific patterns describing
what files you'd like borg to ignore during the backup.  The sample file,
*'excludeLocations.borg'* contains a list of directories to exclude assuming a
standard NextCloud install -- the previews directory and the cache directory.
You need to run *'borg help patterns'* for help on how to specify any additional
exclusion patterns.

### purge timeframe options

Here you can let borg purge know how you want to manage your backup history.
Consult the borg documentation and then copy the relevant options directly into
this line including any spaces, etc.  The example file contains the following as
a staring point:

```Ini
--keep-within=7d --keep-daily=30 --keep-weekly=12 --keep-monthly=-1
```

This would tell borg prune to keep ALL backups made for any reason within the
last 7 days, keep 30 days worth of daily backups, 12 weeks of end-of-week
backups and then an infinite amount of end-of-month backups.

### borg remote location

If you're using rsync, then just have this say *'borg1'*.  If you are using
another provider, you'll have to reference their locally installed copy of borg
relative to your repo path.  You can also leave this blank if your provider does
not run borg locally but your backups/restores will be slower.

### Examples

All fields including pointers to additional files to backup, exclusion patterns
and a remote borg path.  Prune: keep all backups made in the last 14 days.

```Ini
/var/borgbackup
/var/borgbackup/SSHprivate.key
myuser@server001.rsync.net:NCBackup/
myPaSsWoRd
/root/NCscripts/xtraLocations.borg
/root/NCscripts/excludeLocations.borg
--keep-within=14d
borg1
```

No exclusions, keep 14 days end-of-day, 52 weeks end-of-week

```Ini
/var/borgbackup
/root/keys/rsyncPrivate.key
myuser@server001.rsync.net:myBackup/
PaSsWoRd
/var/borgbackup/include.list

--keep-daily=14 --keep-weekly=52
borg1
```

Repo at root, no extra file locations, no exclusions, no remote borg installation. Keep last 30
backups.

```Ini
/root/.borg
/root/.borg/private.key
username@server.tld:backup/
pAsSw0rD


--keep-within=30d

```

## SQL details file

This file contains all the information needed to access your NextCloud SQL
database in order to dump it's contents into a file that can be easily
backed-up. Each line must contain specific information in a specific order.  The
sample file includes this data and example entries.  The file must have the
following information in the following order (**all entries required**):

    1. name of machine hosting mySQL (usually localhost)
    2. name of authorized user
    3. password for above user
    4. name of NextCloud database

For example:

```Ini
localhost
nextcloud
pAsSwOrD
nextcloudDB
```

### Protect your sql details file

This file contains information on how to access your SQL installation therefore,
you **must** protect it.  You should lock it out to your root user.  Putting it
in your root folder is not enough!  Run the following commands to restrict access
to the root user only (assuming filename is *'nc_sql.details'*):

```Bash
# make root the owner
chown root:root nc_sql.details
# restrict access to root only
chmod 600 nc_sql.details
```

## 503 functionality

This script includes an entire section dedicated to copying an html file to act
as an error 503 notification page.  Error 503 is by definition "service
temporarily unavailable" which is exactly the case for your NextCloud server
during a backup since it is in maintenance mode and no logins are permitted.

The script copies whatever file is defined by the *'-5'* parameter (or the
default located at *'scriptpath/503.html'*) to whatever path is defined as the
'webroot' by the *'-w'* parameter.  This means that if you omit the *'-w'*
parameter, the script will necessarily skip this entire process and just issue a
warning to let you know about it.

### Conditional forwarding by your webserver

The script copying the file to the webroot is the easy part.  Your webserver has
to look for the presence of that file and generate a 503 error in order for the
magic to happen.  To do that, you have to include an instruction to that effect
in your default server definition and/or your NextCloud virtual server
definition file depending on your setup.

#### NGINX

You can copy the following code into the relevant server definition(s) on an
NGINX server:

```Perl
server {
    ...
    if (-f /usr/share/nginx/html/503.html) {
        return 503;
    }
...
    error_page 530 @backup
    location @backup {
        root /usr/share/nginx/html;
        rewrite ^(.*)$ /503.html break;
    }
}
```

This tells NGINX that if it finds the file *'503.html'* at the path
*'/usr/share/nginx/html'* (webroot) then return an error code 503.  Next,
rewrite any url to *'domain.tld/503.html'* and thus, display the custom 503
error page.  On the other hand, if it can't find 503.html at the path specified
(i.e. the script has deleted it because the backup is completed), then go about
business as usual.

#### Apache

I don't use apache for anything, ever... so I'm not sure how exactly you'd do
this but I think you'd have to use something like:

```Perl
RewriteEngine On
RewriteCond %{ENV:REDIRECT_STATUS} !=503
RewriteCond "/var/www/503.html" -f
RewriteRule ^ - [R=503,L]
...
ErrorDocument 503 /503.html
...
```

Let me know if that works and I'll update this document accordingly.  Like I
said, I don't use Apache so I can't really test it very easily.

#### Disabling 503 functionality altogether

If you don't want to use the 503 functionality for whatever reason and don't
want your log file junked up with warnings about it, then find the section of
the script file that starts with *'--- Begin 503 section ---'* and either
comment all the lines (put a *'#'* at the beginning of each line) or delete all
the lines until you get to *'--- End 503 section ---'*.

## Scheduling: Cron

After running this script at least once manually to test your settings, you
should schedule it to run automatically so things stay backed up.  This is
easiest with a simple cron job.

1. Open root's crontab:

    ```Bash
    sudo crontab -e
    ```

2. Add your script command line and set the time. I'm assuming your script is
   located at *'/root/NCscripts'*, all files are at their default locations and
   you want to run your backup at 1:07am daily.

    ```Bash
    7 1 * * * /root/NCscripts/backup.sh -d /var/nc_data -n /usr/share/nginx/html/nextcloud -u www-data -l /var/log/backup.log -w /usr/share/nginx/html > /dev/null 2>&1
    ```

    The last part redirects all output to 'null' and forwards any errors to
    'null' also.  You don't need output because the script creates a wonderfully
    detailed log file that you can review :-)
3. Save the file and exit.
4. Confirm by listing the root user's crontab:

    ```Bash
    sudo crontab -l
    ```

## The log file

The script creates a very detailed log file of all major operations along with
any errors and warnings.  Everything is timestamped so you can see how long
things take and when any errors tooks place.  The script includes debugging
notes such as where temp files are located, where it's looking for data, whether
it created/moved/copied files, etc.  All major operations are tagged *'-- [INFO]
message here --'*.  Similarily, warnings are tagged *'-- [WARNING] message here
(code: xxxx) --'* and errors are tagged *'-- [ERROR] message here (code: xxx)
--'*.  Successful operations generate a *'-- [SUCCESS] message here --'* stamp.

This tagging makes it easy for you to set up a log screening program to make
keeping an eye on your backup results easier.  If you plan on using Logwatch
(highly recommended, great program!) then I've done the work for you...

### Using Logwatch

Log-group, conf and service files are included so that you can easily setup
Logwatch to monitor the script's log file and report at your desired detail
level as follows:

    1. 0: Summary of total success, warnings & errors only
    2. 1-4: Actual success, error & warning messages
    3. 5: Same as above, but includes info messages
    4. 6+: Dumps entire raw log file including debugging messages

A detailed breakdown of the files and all options are included in a separate
readme in the *'/etc/logwatch'* folder of this git archive.

### Remember to rotate your logs

The log file generated by this script is fairly detailed so it can grow quite
large over time.  This is especially true if you are using verbose output from
borg for any troubleshoot or for compliance/auditing.  I've included a sample
commented logrotate config file in this git archive at *'/etc/logrotate.d'*
which you can modify and drop into that same directory on your Debian/Ubuntu
system.  If you are using another log rotating solution, then please remember to
configure it so that your log files don't get overwhelmingly large should you
need to parse them if something goes wrong with your backups.

## Final notes

I think that's everything. If I've forgotten to document something, please let
me know. I know this readme is long but, I hate how much stuff for linux and
open-source programs/scripts in general are so poorly documented especially for
newbies and I didn't want to make that same mistake.

I don't script too often and I'm a horrible programmer, so if you see anything
that can be/should be improved, please let me know or submit your changes!  I
love learning new ways of doing things and getting feedback, so suggestions and
comments are more than welcome.

If this has helped you out, then please visit my blog at
[https://mytechiethoughts.com](https://mytechiethoughts.com) where I solve
problems like this all the time on a shoe-string or zero budget.  Thanks!