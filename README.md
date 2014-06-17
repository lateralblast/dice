![alt tag](https://raw.githubusercontent.com/lateralblast/dice/master/dice.png)

DICE
====

Dell iDRAC Configure Environment

Introduction
------------

A tool written in Perl that uses the Expect module to automate iDRAC configuration.

License
-------

This software is licensed as CC-BA (Creative Commons By Attrbution)

http://creativecommons.org/licenses/by/4.0/legalcode

Usage
-----

```
$ dice.pl -m model -i hostname -p password -[n,e,f,g]

-n:	 Change Default password
-e:	 Enable custom settings
-g:	 Check firmware version
-f:	 Update firmware if required
-a:	 Perform all steps
-t:	 Run in test mode (don't do firmware update)
-F:	 Print firmware information
-X:	 Enable Flex Address (this will reset hardware)
-D:	 Dump firmware to file (hostname_fw_dump)
-T:	 Dump firmware to file (hostname_fw_dump) and print in Twiki format
```

Requirements
------------

The following Perl modules are required:

- Expect
- Getopt::Std
- Net::FTP
- File::Slurp
- File::Basename

