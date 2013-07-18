duit
====

Dell Update iDRAC Tool

A tool written in Perl that uses the Expect module to automate iDRAC configuration.

Usage
=====

	./duit.pl -h

	 v. 0.0.9 [Richard Spindler <richard@lateralblast.com.au>]

	Usage: ./dui.pl -m model -i hostname -p password -[n,e,f,g]

	-n Change Default password
	-e Enable custom settings
	-g Check firmware version
	-f Update firmware if required
	-a Perform all steps
	-t Run in test mode (don't do firmware update)
	-F Print firmware information
	-X Enable Flex Address (this will reset hardware)
	-D Dump firmware to file (hostname_fw_dump)
	-T Dump firmware to file (hostname_fw_dump) and print in Twiki format


