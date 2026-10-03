# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.4] - 2026-10-03

### Changed
- Script cleaned up to follow Perl best practices: `use warnings`, no global state beyond a small set of file-level lexicals, and a `main()` sub instead of top-level code
- Site settings moved into a single `%config` hash at the top of the script
- Racadm commands are built as a plain list (`build_commands`) instead of `"prompt,command"` strings, so commands may now contain commas
- Usage text is a here-doc, and the node/chassis model pattern is defined once
- Firmware dump parser simplified (fabric lookup table, shared blade heading helper, no unused variables); output is unchanged
- Invalid command line options now print usage and exit with an error
- Errors go to STDERR through a single `fail()` helper
- Required modules reduced to Expect: File::Slurp is replaced by a plain file read, and the unused Net::FTP and File::Basename are dropped

### Fixed
- Version banner (`-V`, `-h`) now shows the script name, which was always blank
- `-v` now controls verbose output (it was checked as `-V`, which exits earlier)
- Removed the unused temp directory (`/var/log/dice` or `~/.dice`) that was created on every run

### Removed
- Dead code: commented-out commands, unused variables and subs, and the `uname`/`id` calls

## [0.1.3] - 2026-10-03

### Added
- `-v` is now accepted by the option parser (verbose)
- Error messages for a missing host name (`-i`) or password (`-p`)
- `$ntp_server_1` and `$ntp_server_2` settings, separate from the DNS servers

### Changed
- `-T` now implies `-D` (dump firmware, then print Twiki format)
- `-a` now detects the hardware model when `-m` is not given
- Options that are not implemented (`-f`, `-g`, `-F`, `-Z`) now exit with a message instead of silently doing nothing
- Firmware dump waits for each racadm command to finish so the whole dump is logged
- `rm` and `mkdir` shell calls replaced with `unlink` and `mkdir`

### Fixed
- `-t` (test mode) no longer changes the iDRAC password with `-n` or `-a`
- Email address commands were never sent (`"$,"` was read as a Perl variable)
- Email address was always empty because a local variable hid the global
- SSH host key prompt is only answered if it appears, so `yes` is no longer sent as the password
- `ssh` is started without a shell, so host names can't inject commands
- Root detection used `id` instead of `id -u` because of a `= ~` typo
- Duplicate `-h` handling removed
- `exit_idrac` could not match the `$ ` prompt and always waited for the timeout
- Firmware dump parser trimmed with `chop` instead of removing trailing whitespace, and used `[A-z]` ranges

## [0.1.2] - 2026-10-03

### Added
- cpanfile listing required Perl modules
- Automatic installation of missing Perl modules into ~/perl5 at startup

### Fixed
- `push(@cfg_array = ...)` for `setractime`, which is a compile error on modern Perl

### Changed
- License changed to CC BY-NC-SA 4.0 and LICENSE file added
- Changelog converted to CHANGELOG.md

## [0.1.1] - 2014-06-12

### Changed
- Updated documentation and license

## [0.1.0] - 2013-07-14

### Changed
- Code cleanup

## [0.0.9] - 2013-07-13

### Added
- Initial commit to GitHub

## [0.0.8] - 2011-08-05

### Changed
- Many cleanups to firmware dump support

## [0.0.7] - 2011-07-14

### Added
- Firmware dump support (including Twiki output)

## [0.0.6] - 2011-05-20

### Added
- Syslog configuration for the chassis
- SMTP server configuration

### Fixed
- NTP not being enabled

## [0.0.5] - 2011-03-21

### Changed
- Modified serial over IPMI config for iDRAC6

## [0.0.4] - 2011-01-25

### Added
- Support for setting up serial over IPMI

## [0.0.3] - 2010-06-11

### Added
- Command to enable virtual media

## [0.0.2] - 2010-06-09

### Added
- Monash configs, including alerts

## [0.0.1] - 2010-06-05

### Added
- Initial port of suit to Dell
