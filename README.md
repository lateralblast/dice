![DICE](https://raw.githubusercontent.com/lateralblast/dice/master/dice.png)

# DICE

Dell iDRAC Configure Environment

## Introduction

A tool written in Perl that uses the Expect module to automate iDRAC configuration.

## Usage

```
$ dice.pl -m model -i hostname -p password -[n,e,f,g]

-n:  Change default password
-e:  Enable custom settings
-g:  Check firmware version (not yet implemented)
-f:  Update firmware if required (not yet implemented)
-a:  Perform all steps
-t:  Run in test mode (print the commands instead of sending them)
-F:  Print firmware information (not yet implemented)
-X:  Enable Flex Address (this will reset hardware)
-D:  Dump firmware to file (hostname_fw_dump)
-d:  Process an existing firmware dump file (hostname_fw_dump)
-T:  Dump firmware to file (hostname_fw_dump) and print in Twiki format
-v:  Verbose output
-V:  Print version information
-h:  Print help
```

Site-specific settings (syslog, DNS, NTP, SMTP, time zone and email address) are set
at the top of `dice.pl` and need to be edited before use.

## Requirements

The Perl module Expect is required (see `cpanfile`). Everything else used is
part of core Perl.

If it is missing it is installed automatically into `~/perl5` the first time the
script runs. To install them manually:

```
$ cpanm --installdeps .
```

## License

This software is licensed under CC BY-NC-SA 4.0 (Creative Commons
Attribution-NonCommercial-ShareAlike 4.0 International). See the
[LICENSE](LICENSE) file.

## Help Support Development

If you find this software useful and would like to support its development, please consider buying me a coffee:

https://ko-fi.com/richardatlateralblast
