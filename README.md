=Watch Folder - File Uploader Script=

==Introduction==

BASH script that monitors a watch folder and uploads new files via HTTP POST (ie. via curl).  Also supports upto _n_ retry attempts, and also handle purging of files that were already transferred successfully.

Script is designed to be executed via a cron job.  Works on Linux and Windows via Cygwin.

<img src="https://f.cloud.github.com/assets/3783092/226153/8603fcb6-861c-11e2-93d5-390bb7819964.png" />

==Usage==

<pre>
transfer.sh -dir <watch directory> -retry <retry count> -uri <http endpoint> \
    -purge <min days before purging> [-prefix <log filename prefix>]

transfer.sh -dir /var/log/service/ -retry 5 -uri http://host/log.cgi -purge 5 -prefix db
</pre>

==Example Flow==

<pre>
Given this cron:

0 0 * * * /opt/xfer/transfer.sh -dir /var/log/service/ -retry 2 -uri http://host/log.cgi -purge 2

+--------------+--------------------------------------------------------------------------+
|              |    DAY 1     |     DAY 2    |    DAY 3*    |     DAY 4    |    DAY 5     |
+--------------+--------------------------------------------------------------------------+
| Watch Folder | 20130101.log | 20130102.log | 20130103.log | 20130104.log | 20130105.log |
|              |              |              |              |              |              |
+--------------+--------------+--------------+--------------+--------------+--------------+
| Retry #1     |              |              |              | 20130103.log |              |
|      Folder  |              |              |              |              |              |
+--------------+--------------+--------------+--------------+--------------+--------------+
| Retry #2     |              |              |              |              |              |
|      Folder  |              |              |              |              |              |
+--------------+--------------+--------------+--------------+--------------+--------------+
| Success      |              | 20130101.log | 20130102.log | 20130102.log | 20130103.log |
|      Folder  |              |              | 20130101.log |              |              |
+--------------+--------------+--------------+--------------+--------------+--------------+
| Failed       |              |              |              |              |              |
|      Folder  |              |              |              |              |              |
+--------------+--------------+--------------+--------------+--------------+--------------+

* On Day 3, the HTTP HOST is unavailable (transaction failed), and the file got moved to
  retry #1 folder for the next attempt.

* On Day 4, the file 20130101.log got automatically purged (same with 20130102.log on day 5).

</pre>

==Notes==

  * Can easily be modified to do HTTP PUT for WEBDAV.
