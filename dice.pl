#!/usr/bin/env perl

# Name:         dice (Dell iDRAC Configure Environment)
# Version:      0.1.4
# Release:      1
# License:      CC BY-NC-SA (Creative Commons Attribution-NonCommercial-ShareAlike 4.0)
#               https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode
# Group:        System
# Source:       N/A
# URL:          http://lateralblast.com.au/
# Distribution: UNIX
# Vendor:       Lateral Blast
# Packager:     Richard Spindler <richard@lateralblast.com.au>
# Description:  Perl script to log into iDRACs and configure them

use strict;
use warnings;

# Make sure required modules are installed, installing any missing ones
# (via cpanm or cpan) into ~/perl5 so no root access is needed

BEGIN {
  my $local_lib = "$ENV{HOME}/perl5";
  require lib;
  lib->import("$local_lib/lib/perl5");
  my @modules = qw(Expect);
  my @missing = grep { !eval "require $_; 1" } @modules;
  if (@missing) {
    my $installer = (grep { -x "$_/cpanm" } split(/:/, $ENV{PATH}))
                  ? "cpanm --notest --local-lib $local_lib"
                  : "cpan -T";
    print "Installing missing Perl modules: @missing\n";
    local $ENV{PERL_MM_USE_DEFAULT} = 1;
    local $ENV{PERL_MM_OPT}         = "INSTALL_BASE=$local_lib";
    local $ENV{PERL_MB_OPT}         = "--install_base $local_lib";
    system("$installer @missing");
    lib->import("$local_lib/lib/perl5");
    foreach my $module (@missing) {
      eval "require $module; 1" or die "Failed to install required module $module\n";
    }
  }
}

use Expect;
use Getopt::Std;

# Site specific settings: edit these before use

my %config = (
  time_zone   => 'Australia/Melbourne',
  syslog_1    => 'XXX.XXX.XXX.XXX',
  syslog_2    => 'XXX.XXX.XXX.XXX',
  ntp_1       => 'XXX.XXX.XXX.XXX',
  ntp_2       => 'XXX.XXX.XXX.XXX',
  smtp_server => 'XXX.XXX.XXX.XXX',
  email_list  => 'blah@blah.com',
);

# Default iDRAC root password, used to log in when changing the password

my $default_password = 'calvin';

# Seconds to wait for output from the iDRAC

my $pause = 8;

# Hardware models that are a rackmount or a blade rather than a chassis

my $node_model = qr/r[0-9][1-9]|m[0-9][1-9]/;

# State shared between subs

my %option;
my %script_info;
my $ssh_session;
my $console_prompt = '';
my $firmware_dump_file;

main();

sub main {
  %script_info = read_script_header();
  getopts('i:m:p:nedDvVfgahZtFXT', \%option) or do {
    print_usage();
    exit 1;
  };
  if ($option{h}) {
    print_usage();
    exit 0;
  }
  if ($option{V}) {
    print_version();
    exit 0;
  }
  # Options that are accepted but have no implementation yet
  foreach my $unsupported (qw(f g F Z)) {
    fail("Option -$unsupported is not implemented") if $option{$unsupported};
  }
  if (!$option{i}) {
    print "Host name required (-i)\n";
    print_usage();
    exit 1;
  }
  $firmware_dump_file = "$option{i}_fw_dump";
  # -d processes an existing firmware dump, or gets one if it does not exist
  if ($option{d}) {
    if (-e $firmware_dump_file) {
      process_firmware_dump();
      exit 0;
    }
    print "\nFirmware dump file $firmware_dump_file does not exist\n";
    print "Attempting to get firmware information from $option{i}\n\n";
    $option{D} = 1;
  }
  # -T implies dumping the firmware information
  $option{D} = 1 if $option{T} && !$option{d};
  initiate_ssh_session();
  if ($option{e} || $option{a} || $option{D}) {
    $option{m} = determine_hardware() if !$option{m};
    $option{m} = lc($option{m});
  }
  change_idrac_password() if $option{n} || $option{a};
  configure_idrac()       if $option{e} || $option{a};
  if ($option{D}) {
    dump_firmware();
    exit_idrac();
    process_firmware_dump();
    exit 0;
  }
  exit_idrac();
  return;
}

# Print an error and exit

sub fail {
  my $message = shift;
  print STDERR "$message\n";
  exit 1;
}

# Read the information in the header comments of this script

sub read_script_header {
  my %info;
  open(my $fh, '<', $0) or fail("Cannot read $0: $!");
  while (my $line = <$fh>) {
    last if $line =~ /^use /;
    $info{$1} //= $2 if $line =~ /^#\s+(\w+):\s+(.+?)\s*$/;
  }
  close($fh);
  return %info;
}

sub print_version {
  print "\n$script_info{Name} v. $script_info{Version} [$script_info{Packager}]\n\n";
  return;
}

sub print_usage {
  print_version();
  print <<"USAGE";
Usage: $0 -m model -i hostname -p password -[n,e,f,g]

-n:  Change Default password
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

USAGE
  return;
}

# Parse the firmware dump into different formats

sub process_firmware_dump {
  # The dump is raw terminal output, so fields are often missing
  no warnings 'uninitialized';
  open(my $fh, '<', $firmware_dump_file) or fail("Cannot read $firmware_dump_file: $!");
  my @raw_firmware = <$fh>;
  close($fh);
  my %fabric_name = (1 => 'A1', 2 => 'A2', 3 => 'B1', 4 => 'B2', 5 => 'C1', 6 => 'C2');
  my $twiki = $option{T};
  my $start_processing = 0;
  my ($blade_no, $component, $version, $install_date, $model_no, $idrac_no);
  my ($hostname, $svctag, $fabric_no, $extension);
  my (@hostnames, @serials);
  $model_no = '';
  if ($twiki) {
    print "<br />\n";
    print "---+ Chassis: $option{i}\n";
    print "<br />\n";
    print "|*Slot*|*Model*|*Hostname*|*Serial*|\n";
  }
  foreach my $record (@raw_firmware) {
    chomp($record);
    $record =~ s/\s+\(/ \(/g;
    if ($record =~ /^Switch/ && $record =~ /:|Not Installed/) {
      ($fabric_no, $component) = split(/  \s+/, $record);
      $fabric_no =~ s/Switch-//g;
      $fabric_no = $fabric_name{$fabric_no} // $fabric_no;
      if ($twiki) {
        $component =~ s/Present//g;
        $component =~ s/GbE/Gb/g;
        print "|$fabric_no|$component|N/A|N/A|\n";
      }
    }
    if ($record =~ /SLOT-/) {
      (undef, $hostname)    = split(/SLOT-/, $record);
      ($blade_no, $hostname) = split(/ \s+/, $hostname);
      $blade_no =~ s/^0//;
      $hostname =~ s/\s+$//;
      $hostnames[$blade_no] = $hostname;
    }
    if ($record =~ /Chassis/ && $record =~ /^Server/ && $record !~ /:/) {
      (undef, undef, undef, undef, $svctag) = split(/  \s+/, $record);
      $svctag =~ s/\s+$//;
      $blade_no   = 0;
      $serials[0] = $svctag;
      if ($twiki) {
        $model_no =~ s/GbE/Gb/g;
        print "|$blade_no|$model_no|$hostnames[$blade_no]|!$serials[$blade_no]|\n";
      }
    }
    if ($record =~ /Present/ && $record =~ /^Server/ && $record !~ /:/) {
      ($blade_no, undef, undef, undef, $svctag) = split(/  \s+/, $record);
      $blade_no =~ s/Server-//g;
      $svctag   =~ s/\s+$//;
      $serials[$blade_no] = $svctag;
    }
    if ($record =~ /PowerEdgeM/) {
      ($blade_no, $version, $model_no, $idrac_no) = split(/  \s+/, $record);
      $blade_no =~ s/server-//g;
      ($model_no) = split(/ \s+/, $model_no) if $model_no =~ / /;
      $model_no =~ s/PowerEdge//g;
      if ($twiki) {
        $model_no = '!M710HD' if $model_no =~ /M710HD/;
        $model_no =~ s/GbE/Gb/g;
        print "|$blade_no|$model_no|$hostnames[$blade_no]|!$serials[$blade_no]|\n";
      }
    }
    $start_processing = 1 if $record =~ /\$ racadm getversion -l/;
    next if !$start_processing;
    if ($record =~ /^server-/ && $record !~ /extension/) {
      ($blade_no, $component, $version, $install_date) = split(/ \s+/, $record);
      $blade_no =~ s/server-//g;
      print_blade_heading($blade_no, $hostnames[$blade_no]) if $twiki;
      print "|*Component*|*Version*|*Install Date*|\n"       if $twiki;
    }
    elsif ($record =~ /ERROR/ && $record =~ /extension/) {
      ($blade_no, $extension) = split(' is an extension of the server in slot ', $record);
      $blade_no =~ s/[A-Za-z :]//g;
      if ($twiki && $blade_no =~ /[0-9]/) {
        print_blade_heading($blade_no, $hostnames[$extension], ' (extension)');
      }
    }
    elsif ($record =~ /ERROR/) {
      (undef, $blade_no) = split('LC is not supported for server ', $record);
      $blade_no =~ s/\s+$//;
      $blade_no =~ s/[A-Za-z]//g;
      if ($twiki && $blade_no =~ /[0-9]/) {
        print_blade_heading($blade_no, $hostnames[$blade_no]);
        print "Firmware needs updating to display details\n";
      }
    }
    else {
      (undef, $component, $version, $install_date) = split(/ \s+/, $record);
    }
    if ($twiki) {
      $install_date =~ s/\s+$//;
      if ($install_date !~ /Re|Ro/ && $component =~ /[A-Za-z]/ && $record !~ /</) {
        print "|$component|$version|$install_date|\n";
      }
    }
  }
  return;
}

# Print a blade heading in Twiki format

sub print_blade_heading {
  my ($blade_no, $hostname, $suffix) = @_;
  $suffix //= '';
  print "<br />\n";
  print "---++ Blade $blade_no: $hostname$suffix\n";
  print "<br />\n";
  return;
}

# Dump firmware information from racadm

sub dump_firmware {
  if ($option{m} =~ /m1000e/) {
    send_racadm('racadm getmodinfo -A');
    send_racadm('racadm getslotname');
    send_racadm('racadm getmacaddress -a');
    send_racadm('racadm getversion');
    foreach my $server (1 .. 16) {
      send_racadm("racadm getversion -l -m server-$server");
    }
    # Leave a fresh prompt for exit_idrac to consume
    $ssh_session->send("\n");
  }
  return;
}

# Send a racadm command and wait for it to finish (output is logged as it is read)

sub send_racadm {
  my $command = shift;
  # Read and log anything still pending, then start with an empty buffer
  $ssh_session->expect(1, '-re', '\0no-such-output\0');
  $ssh_session->clear_accum();
  $ssh_session->send("$command\n");
  $ssh_session->expect(30, '-re', quotemeta($console_prompt) . '\s*\z');
  return;
}

# Work out which model we are running on

sub determine_hardware {
  $ssh_session->send("racadm getsysinfo\n");
  $ssh_session->expect($pause, '-re', 'System Model');
  my $output = $ssh_session->after() // '';
  $ssh_session->send("\n");
  ($output) = split(/\n/, $output);
  $output //= '';
  $output =~ s/=//g;
  $output =~ s/^\s+//;
  $output = 'PowerEdge M1000e' if $output =~ /CMC/;
  return $output;
}

# Log into the iDRAC

sub initiate_ssh_session {
  my $logged_in = 0;
  my $login_password;
  if (!$option{p} && !$option{n} && !$option{a}) {
    fail('Password required (-p)');
  }
  $login_password = ($option{n} || $option{a}) ? $default_password : $option{p};
  unlink($firmware_dump_file) if $option{D} && -e $firmware_dump_file;
  $option{i} .= '-mgt' if $option{i} !~ /-mgt/;
  $ssh_session = Expect->spawn('ssh', "root\@$option{i}")
    or fail('Cannot start ssh');
  if ($option{D}) {
    $ssh_session->log_stdout(0);
    $ssh_session->log_file($firmware_dump_file);
  }
  # Only accept the host key if ssh actually asks about it
  $ssh_session->expect($pause,
    [ qr/yes\/no/ => sub {
        my $session = shift;
        $session->send("yes\n");
        exp_continue;
      } ],
    [ qr/password:/ => sub {
        my $session = shift;
        $session->send("$login_password\n");
        $logged_in = 1;
      } ],
  );
  fail("Did not get a password prompt from $option{i}") if !$logged_in;
  $console_prompt = defined $ssh_session->expect($pause, '-re', 'Welcome')
                  ? '$ '
                  : '/admin1-> ';
  return;
}

sub exit_idrac {
  $ssh_session->expect($pause, $console_prompt);
  $ssh_session->send("exit\n");
  $ssh_session->soft_close();
  $ssh_session->log_file(undef);
  $ssh_session->log_stdout(1);
  return;
}

# Test to see if it's a blade/server or a chassis and work out the root id

sub determine_if_blade {
  $ssh_session->send("getchassisname\n");
  my $is_blade = defined $ssh_session->expect($pause, '-re', 'Invalid command|COMMAND NOT RECOGNIZED');
  my $root_id  = $is_blade ? 2 : 1;
  print 'Found a ', ($is_blade ? 'Blade or Server' : 'Blade Chassis'), "\n" if $option{v};
  $ssh_session->send("\n");
  return ($is_blade, $root_id);
}

# Change iDRAC password

sub change_idrac_password {
  my (undef, $root_id) = determine_if_blade();
  my $racadm_command = "racadm config -g cfgUserAdmin -o cfgUserAdminPassword -i $root_id";
  if ($option{v} || $option{t}) {
    print "Sending the following commands:\n";
    print "$racadm_command ********\n";
  }
  $ssh_session->send("$racadm_command $option{p}\n") if !$option{t};
  return;
}

# Build the list of racadm commands to send

sub build_commands {
  my @commands;
  my ($is_blade, $root_id) = determine_if_blade();
  my $is_node = $option{m} =~ $node_model;
  push(@commands,
    "racadm config -g cfgRemoteHosts -o cfgRhostsSyslogServer1 $config{syslog_1}",
    "racadm config -g cfgRemoteHosts -o cfgRhostsSyslogServer2 $config{syslog_2}",
    'racadm config -g cfgRemoteHosts -o cfgRhostsSyslogEnable 1',
  );
  if ($is_blade) {
    push(@commands,
      'racadm config -g cfgRacTuning -o cfgRacTuneWebserverEnable 1',
      'racadm config -g cfgSerial -o cfgSerialSshEnable 1',
      'racadm config -g cfgSerial -o cfgSerialTelnetEnable 0',
      "racadm config -g cfgUserAdmin -o cfgUserAdminEmailAddress -i $root_id $config{email_list}",
      "racadm config -g cfgUserAdmin -o cfgUserAdminEmailEnable -i $root_id 1",
      "racadm config -g cfgRemoteHosts -o cfgRhostsSmtpServerIpAddr $config{smtp_server}",
      "racadm config -g cfgEmailAlert -o cfgEmailAlertEnable -i $root_id 1",
      'racadm config -g cfgRacVirtual -o cfgVirMediaAttached 1',
    );
  }
  else {
    if (!$is_node) {
      push(@commands, "setchassisname $option{i}");
      if ($option{X}) {
        # Set Flex Addressing on the blade chassis
        push(@commands, map { "setflexaddr -f $_ 1" } qw(A B C iDRAC));
        push(@commands, map { "setflexaddr -i $_ 1" } 1 .. 16);
      }
      push(@commands,
        "racadm setractime -z $config{time_zone}",
        'racadm config -g cfgAlerting -o cfgAlertingEnable 1',
        "racadm config -g cfgAlerting -o cfgAlertingSourceEmailName cmc\@$option{i}",
        "racadm config -g cfgRemoteHosts -o cfgRhostsSmtpServerIpAddr $config{smtp_server}",
      );
    }
    push(@commands,
      "racadm config -g cfgRemoteHosts -o cfgRhostsNtpServer1 $config{ntp_1}",
      "racadm config -g cfgRemoteHosts -o cfgRhostsNtpServer2 $config{ntp_2}",
      'racadm config -g cfgRemoteHosts -o cfgRhostsNtpEnable 1',
    );
  }
  if ($is_node) {
    push(@commands,
      'racadm config -g cfgIpmiLan -o cfgIpmiLanEnable 1',
      'racadm config -g cfgIpmiLan -o cfgIpmiLanAlertEnable 1',
    );
  }
  # Chassis location is worked out from the host name
  if ($option{i} =~ /28/ && $option{m} !~ /m[0-9][1-9]/) {
    push(@commands, 'racadm setsysinfo -c chassislocation "Building 28"');
  }
  if ($option{i} =~ /224/) {
    push(@commands, 'racadm setsysinfo -c chassislocation "Building 224"');
  }
  push(@commands, "racadm config -g cfgEmailAlert -o cfgEmailAlertAddress -i $root_id $config{email_list}");
  return @commands;
}

# Configure iDRAC with custom settings

sub configure_idrac {
  my $show = $option{v} || $option{t};
  print "Sending the following commands:\n" if $show;
  $ssh_session->clear_accum();
  foreach my $command (build_commands()) {
    print "$command\n" if $show;
    next if $option{t};
    $ssh_session->expect(25, $console_prompt);
    $ssh_session->send("$command\n");
  }
  return;
}
