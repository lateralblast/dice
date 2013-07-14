#!/usr/bin/env perl

# Name:         duit (Dell Update iDRAC Tool)
# Version:      0.1.0
# Release:      1
# License:      Open Source
# Group:        System
# Source:       N/A
# URL:          http://lateralblast.com.au/
# Distribution: UNIX
# Vendor:       Lateral Blast
# Packager:     Richard Spindler <richard@lateralblast.com.au>
# Description:  Perl script to log into iDRACs and configure them

use strict;
use Expect;
use Getopt::Std;
use Net::FTP;
use File::Slurp;
use File::Basename;

# Set up some host configuration variables

my $time_zone="Australia/Melbourne";
my $syslog_server_1="XXX.XXX.XXX.XXX"; 
my $syslog_server_2="XXX.XXX.XXX.XXX";
my $dns_server_1="XXX.XXX.XXX.XXX";
my $dns_server_2="XXX.XXX.XXX.XXX";
my $smtp_server="XXX.XXX.XXX.XXX";
my $console_prompt="";

# General setup

my $script_file=$0; 
my $ssh_session;
my @standard_input; 
my %option; 
my @command_line;
my $verbose;
my @cfg_array; 
my @firmware_array; 
my $email_list="blah\@blah.com";
my $pause=8; 
my $os_vers=`uname -a`; 
my $temp_dir;
my $firmware_dump_file;
my $script_info;
my $version_info;
my $packager_info;
my $vendor_info;
my $script_name=$0;
my @script_file;


# Check local config

check_local_config();

# Get command line options

getopts("i:m:p:nedDVfgahZtFXT",\%option) or print_usage();

# Search script header for information

sub search_script {
  my $search_string=$_[0];
  my $result;
  my $header;
  if ($script_file[0]!~/perl/) {
    @script_file=read_file($script_name);
  }
  my @search_info=grep{/^# $search_string/}@script_file;
  ($header,$result)=split(":",$search_info[0]);
  $result=~s/^\s+//;
  chomp($result);
  return($result);
}

# Check local config
# once you have done the pod work uncomment the command to make the man page

sub check_local_config {
  my $man_file; my $pod_exe; my $user_id;
  my $home_dir=`echo \$HOME`;
  my $dir_name=basename($script_name);
  $vendor_info=search_script("Vendor");
  $packager_info=search_script("Packager");
  $version_info=search_script("Version");
  if ($os_vers=~/SunOS/) {
    $user_id=`id`;
  }
  else {
    $user_id=`id -u`;
  }
  chomp($user_id);
  chomp($home_dir);
  if ($user_id=~/^0$/) {
    $temp_dir="/var/log/$dir_name";
  }
  else {
    $temp_dir="$home_dir/.$dir_name";
  }
  if (! -e "$temp_dir") {
    system("mkdir $temp_dir");
  }
  return;
}

# If passed -h print help
# Uncomment man command when you have filled out the pod section

if ($option{'h'}) {
  print_usage();
  #system("man $script_name");
  exit;
}

# If passed -h print help
# Uncomment man command when you have filled out the pod section

if ($option{'h'}) {
  print_usage();
  exit;
}

# If passed -V print version info

if ($option{'V'}) {
  print_version();
  exit
}

# Print version information

sub print_version {
  print "\n";
  print "$script_info v. $version_info [$packager_info]\n";
  print "\n";
  return;
}

# Print help information

sub print_usage {
  print_version();
  print "Usage: $script_name -m model -i hostname -p password -[n,e,f,g]\n"; 
  print "\n";
  print "-n Change Default password\n";
  print "-e Enable custom settings\n";
  print "-g Check firmware version\n";
  print "-f Update firmware if required\n";
  print "-a Perform all steps\n"; 
  print "-t Run in test mode (don't do firmware update)\n";
  print "-F Print firmware information\n"; 
  print "-X Enable Flex Address (this will reset hardware)\n";
  print "-D Dump firmware to file (hostname_fw_dump)\n";
  print "-T Dump firmware to file (hostname_fw_dump) and print in Twiki format\n";
  print "\n";
  return;
}

# If given -d process firmware dump

if ($option{'d'}) {
  $firmware_dump_file="$option{'i'}_fw_dump";
  if (!-e "$firmware_dump_file") {
    print "\n";
    print "Firmware dump file $firmware_dump_file does not exist\n";
    print "Attempting to get firmware information from $option{'i'}\n";
    print "\n";
    $option{'D'}=1;
  }
  else {
    process_firmware_dump();
    exit();
  }
}

# Initiate SSH session

initiate_ssh_session();

# Handle remain command line arguments

if (($option{'f'})||($option{'g'})||($option{'e'})||($option{'D'})) {
  if (!$option{'m'}) {
    $option{'m'}=determine_hardware();
  }
  $option{'m'}=lc($option{'m'});
}

if (($option{'n'})||($option{'a'})) {
  change_idrac_password();
}

if (($option{'e'})||($option{'a'})) {
  configure_idrac();
}

# Dump firmware information

if ($option{'D'}) {
  dump_firmware();
}

if ($option{'D'}) {
  exit_idrac();
  process_firmware_dump();
  exit;
}

# Close SSH session

exit_idrac();

# Parse the firmware dump into different formats

sub process_firmware_dump {
  my @raw_firmware=read_file($firmware_dump_file);
  my $record; 
  my $blade_no;
  my $start_processing=0; 
  my $chassis;
  my $component; 
  my $version; 
  my $install_date;
  my $header; 
  my $model_no; 
  my $idrac_no;
  my @hostnames; 
  my $hostname; 
  my @serials;
  my $serial_no; 
  my $presence; 
  my $power;
  my $health; 
  my $svctag; 
  my $fabric_no;
  my $extension;
  if ($option{'T'}) {
    print "<br />\n";
    print "---+ Chassis: $option{'i'}\n";
    print "<br />\n";
    print "|*Slot*|*Model*|*Hostname*|*Serial*|\n";
  }
  foreach $record (@raw_firmware) {
    chomp($record);
    $record=~s/\s+\(/ \(/g;
    if (($record=~/^Switch/)&&($record=~/:|Not Installed/)) {
      ($fabric_no,$component,$header,$header,$header,$header)=split(/  \s+/,$record);
      $fabric_no=~s/Switch\-//g;
      if ($fabric_no=~/1/) {
        $fabric_no="A1";
      }
      if ($fabric_no=~/2/) {
        $fabric_no="A2";
      }
      if ($fabric_no=~/3/) {
        $fabric_no="B1";
      }
      if ($fabric_no=~/4/) {
        $fabric_no="B2";
      }
      if ($fabric_no=~/5/) {
        $fabric_no="C1";
      }
      if ($fabric_no=~/6/) {
        $fabric_no="C2";
      }
      if ($option{'T'}) {
        $component=~s/Present//g;
        if ($component=~/GbE/) {
          $component=~s/GbE/Gb/g;
        }
        print "|$fabric_no|$component|N/A|N/A|\n";
      }
    }
    if ($record=~/SLOT-/) {
      ($header,$hostname)=split(/SLOT\-/,$record);
      ($blade_no,$hostname)=split(/ \s+/,$hostname);
      $blade_no=~s/^0//g;
      chop($hostname);
      $hostnames[$blade_no]=$hostname;
    }
    if (($record=~/Chassis/)&&($record=~/^Server/)&&($record!~/\:/)) {
      ($header,$presence,$power,$health,$svctag)=split(/  \s+/,$record);
      chop($svctag);
      $blade_no=0;
      $serials[0]=$svctag;
      if ($option{'T'}) {
        if ($model_no=~/GbE/) {
          $model_no=~s/GbE/Gb/g;
        }
        print "|$blade_no|$model_no|$hostnames[$blade_no]|!$serials[$blade_no]|\n";
      }
    }
    if (($record=~/Present/)&&($record=~/^Server/)&&($record!~/\:/)) {
      ($blade_no,$presence,$power,$health,$svctag)=split(/  \s+/,$record);
      $blade_no=~s/Server\-//g;
      chop($svctag);
      $serials[$blade_no]=$svctag;
    }
    if ($record=~/PowerEdgeM/) {
      ($blade_no,$version,$model_no,$idrac_no,$header)=split(/  \s+/,$record);
      $blade_no=~s/server\-//g;
      if ($model_no=~/ /) {
        ($model_no,$header)=split(/ \s+/,$model_no);
      }
      $model_no=~s/PowerEdge//g;
      if ($option{'T'}) {
        if ($model_no=~/M710HD/) {
          $model_no="!M710HD";
        }
        if ($model_no=~/GbE/) {
          $model_no=~s/GbE/Gb/g;
        }
        print "|$blade_no|$model_no|$hostnames[$blade_no]|!$serials[$blade_no]|\n";
      }
    }
    if (($record=~/\$ racadm getversion -l/)) {
      $start_processing=1;
    }
    if ($start_processing eq 1) {
      if (($record=~/^server\-/)&&($record!~/extension/)) {
        ($blade_no,$component,$version,$install_date)=split(/ \s+/,$record);
        $blade_no=~s/server\-//g;
        if ($option{'T'}) {
          print "<br />\n";
          print "---++ Blade $blade_no: $hostnames[$blade_no]\n";
          print "<br />\n";
          print "|*Component*|*Version*|*Install Date*|\n";
        }
      }
      else {
        if ($record=~/ERROR/) {
          if ($record=~/extension/) {
            ($blade_no,$extension)=split(" is an extension of the server in slot ",$record);
            $blade_no=~s/[A-z]//g;
            $blade_no=~s/ //g;
            $blade_no=~s/\://g;
            if ($blade_no=~/[0-9]/) {
              if ($option{'T'}) {
                print "<br />\n";
                print "---++ Blade $blade_no: $hostnames[$extension] (extension)\n";
                print "<br />\n";
              }
            }
          }
          else {
            ($header,$blade_no)=split("LC is not supported for server ",$record);
            chop($blade_no);
            $blade_no=~s/[A-z]//g;
            if ($blade_no=~/[0-9]/) {
              if ($option{'T'}) {
                print "<br />\n";
                print "---++ Blade $blade_no: $hostnames[$blade_no]\n";
                print "<br />\n";
                print "Firmware needs updating to display details\n";
              }
            }
          }
        }
        else {
          ($header,$component,$version,$install_date)=split(/ \s+/,$record);
        }
      }
      if ($option{'T'}) {
        chop($install_date);
        if (($install_date!~/Re|Ro/)&&($component=~/[A-z]/)&&($record!~/\</)) {
          print "|$component|$version|$install_date|\n";
        }
      }
    }
  }
  return;
}

# Dump firmware information from racadm

sub dump_firmware {
  my $output; 
  my @firmware_dump;
  my $counter;
  if ($option{'m'}=~/m1000e/) {
    $ssh_session->send("racadm getmodinfo -A\n");
    $ssh_session->send("racadm getslotname\n");
    $ssh_session->send("racadm getmacaddress -a\n");
    $ssh_session->send("racadm getversion\n");
    for ($counter=1; $counter<17; $counter++) {
      $ssh_session->send("racadm getversion -l -m server-$counter\n");
      sleep(5);
    }
  }
  return;
}

# Work out which model we are running on

sub determine_hardware {
  my $output; 
  my @output_array;
  $ssh_session->send("racadm getsysinfo\n");
  $output=$ssh_session->expect($pause,'-re','System Model');
  $output=$ssh_session->after();
  $ssh_session->send("\n");
  @output_array=split('\n',$output);
  $output=$output_array[0];
  chomp($output);
  $output=~s/\=//g;
  $output=~s/^\s+//g;
  if ($output=~/CMC/) {
    $output="PowerEdge M1000e";
  }
  return($output);
}

sub initiate_ssh_session {
  my $result=do_known_host_check();
  my $output;
  if ($option{'D'}) { 
    $firmware_dump_file="$option{'i'}_fw_dump";
    if (-e "$firmware_dump_file") {
      system("rm $firmware_dump_file");
    }
  }
  if ($option{'i'}!~/\-mgt/) {
    $option{'i'}="$option{'i'}-mgt";
  }
  $ssh_session=Expect->spawn("ssh root\@$option{'i'}");
  if ($option{'D'}) {
    $ssh_session->log_stdout(0);
    $ssh_session->log_file("$firmware_dump_file");
  }
  if ($result eq 0) {
    $output=$ssh_session->expect($pause,'-re','yes\/no');
    $ssh_session->send("yes\n");
  }
  if (($option{'n'})||($option{'a'})) {
    $output=$ssh_session->expect($pause,'-re','password:');
    $ssh_session->send("calvin\n");
  }
  else {
    $output=$ssh_session->expect($pause,'-re','password:');
    $ssh_session->send("$option{'p'}\n");
  }
  #$ssh_session->log_stdout(0);
  $output=$ssh_session->expect($pause,'-re','Welcome');
  if ($output eq 1) {
    $console_prompt="\$ ";
  }
  else {
    $console_prompt="/admin1-> ";
  }
  return;
} 

sub do_known_host_check {
  my $result=0; 
  my $host_test;
  my $home_dir; 
  my $host_file; 
  $home_dir=`echo \$HOME`;
  chomp($home_dir);
  $host_file="$home_dir/.ssh/known_hosts";  
  $host_test=`cat $host_file |grep -i '$option{'i'}'`;
  chomp($host_test);
  if ($host_test=~/$option{'i'}/) {
    $result=1;
  }
  return($result);
}
  
sub exit_idrac {
  my $output;
  $output=$ssh_session->expect($pause,'-re',$console_prompt);
  $ssh_session->send("exit\n");
  $ssh_session->log_stdout(1);
  return;
}

# Test to see if it's a blade/server or a chassis and change root_id

sub determine_if_blade {
  my $blade_test=0; 
  my $root_id;
  $ssh_session->send("getchassisname\n");
  $blade_test=$ssh_session->expect($pause,'-re','Invalid command|COMMAND NOT RECOGNIZED');
  if ($blade_test eq 1) {
    if ($option{'v'}) {
      print "Found a Blade or Server\n";
    }
    $root_id="2";
  }
  else {
    if ($option{'v'}) {
      print "Found a Blade Chassis\n";
    }
    $root_id="1";
  }
# $ssh_session->exp_internal(1);
  $ssh_session->send("\n");
  return($blade_test,$root_id);
}

# Change iDRAC password

sub change_idrac_password {
  my $counter; 
  my $record; 
  my $match; 
  my $response; 
  my $output; 
  my $blade_test=1;
  my $racadm_command; 
  my $root_id;
  ($blade_test,$root_id)=determine_if_blade();
  $racadm_command="racadm config -g cfgUserAdmin -o cfgUserAdminPassword -i $root_id $option{'p'}";
  $ssh_session->send("$racadm_command\n");
  return;
}

# Populate array of commands to send to Expect 

sub populate_cfg_array {
  my $counter=0; 
  my $blade_test=0; 
  my $email_list;
  my $root_id;
  # Set NTP Servers
  push(@cfg_array,"$console_prompt,racadm config -g cfgRemoteHosts -o cfgRhostsSyslogServer1 $syslog_server_1");
  push(@cfg_array,"$console_prompt,racadm config -g cfgRemoteHosts -o cfgRhostsSyslogServer2 $syslog_server_2");
  push(@cfg_array,"$console_prompt,racadm config -g cfgRemoteHosts -o cfgRhostsSyslogEnable 1");
  #
  ($blade_test,$root_id)=determine_if_blade();
  if ($blade_test eq 1) {
    # Set Time Zone
    # Enable webserver 
    push(@cfg_array,"$console_prompt,racadm config -g cfgRacTuning -o cfgRacTuneWebserverEnable 1");
    # Enable SSH, Disable Telnet
    #push(@cfg_array,"$console_prompt,racadm config -g cfgSerial -o cfgSerialConsoleEnable 1");
    push(@cfg_array,"$console_prompt,racadm config -g cfgSerial -o cfgSerialSshEnable 1");
    push(@cfg_array,"$console_prompt,racadm config -g cfgSerial -o cfgSerialTelnetEnable 0");
    # Enable and setup alert email 
    push(@cfg_array,"$,racadm config -g cfgUserAdmin -o cfgUserAdminEmailAddress -i $root_id $email_list");
    push(@cfg_array,"$,racadm config -g cfgUserAdmin -o cfgUserAdminEmailEnable -i $root_id 1");
    push(@cfg_array,"$console_prompt,racadm config -g cfgRemoteHosts -o cfgRhostsSmtpServerIpAddr $smtp_server");
    push(@cfg_array,"$console_prompt,racadm config -g cfgEmailAlert -o cfgEmailAlertEnable -i $root_id 1");
    push(@cfg_array,"$console_prompt,racadm config -g cfgRacVirtual -o cfgVirMediaAttached 1 ");
    # Setup DHCP
    #push(@cfg_array,"$console_prompt,racadm config -g cfgLanNetworking -o cfgNicEnable 1");
    #push(@cfg_array,"$console_prompt,racadm config -g cfgLanNetworking -o cfgDNSServersFromDHCP 1");
    #push(@cfg_array,"$console_prompt,racadm config -g cfgLanNetworking -o cfgDNSDomainNameFromDHCP 1");
    #push(@cfg_array,"$,");
  }
  else {
    # If not a rackmount or blade add the following racadm commands to list
    if ($option{'m'}!~/r[0-9][1-9]|m[0-9][1-9]/) {
      push(@cfg_array,"$console_prompt,setchassisname $option{'i'}");
      if ($option{'X'}) {
        # Set Flex Addressing on Blade Chassis
        push(@cfg_array,"$console_prompt,setflexaddr -f A 1");
        push(@cfg_array,"$console_prompt,setflexaddr -f B 1");
        push(@cfg_array,"$console_prompt,setflexaddr -f C 1");
        push(@cfg_array,"$console_prompt,setflexaddr -f iDRAC 1");
        push(@cfg_array,"$console_prompt,setflexaddr -i 1 1");
        push(@cfg_array,"$console_prompt,setflexaddr -i 2 1");
        push(@cfg_array,"$console_prompt,setflexaddr -i 3 1");
        push(@cfg_array,"$console_prompt,setflexaddr -i 4 1");
        push(@cfg_array,"$console_prompt,setflexaddr -i 5 1");
        push(@cfg_array,"$console_prompt,setflexaddr -i 6 1");
        push(@cfg_array,"$console_prompt,setflexaddr -i 7 1");
        push(@cfg_array,"$console_prompt,setflexaddr -i 8 1");
        push(@cfg_array,"$console_prompt,setflexaddr -i 9 1");
        push(@cfg_array,"$console_prompt,setflexaddr -i 10 1");
        push(@cfg_array,"$console_prompt,setflexaddr -i 11 1");
        push(@cfg_array,"$console_prompt,setflexaddr -i 12 1");
        push(@cfg_array,"$console_prompt,setflexaddr -i 13 1");
        push(@cfg_array,"$console_prompt,setflexaddr -i 14 1");
        push(@cfg_array,"$console_prompt,setflexaddr -i 15 1");
        push(@cfg_array,"$console_prompt,setflexaddr -i 16 1");
      }
      push(@cfg_array="$console_prompt,racadm setractime -z $time_zone");
      #push(@cfg_array,"$console_prompt,racadm config -g cfgNetTuning -o cfgNetTuningNicAutone 1");
      push(@cfg_array,"$console_prompt,racadm config -g cfgAlerting -o cfgAlertingEnable 1");
      push(@cfg_array,"$console_prompt,racadm config -g cfgAlerting -o cfgAlertingSourceEmailName cmc\@$option{'i'}");
      push(@cfg_array,"$console_prompt,racadm config -g cfgRemoteHosts -o cfgRhostsSmtpServerIpAddr $smtp_server");
    }
    push(@cfg_array,"$console_prompt,racadm config -g cfgRemoteHosts -o cfgRhostsNtpServer1 $dns_server_1");
    push(@cfg_array,"$console_prompt,racadm config -g cfgRemoteHosts -o cfgRhostsNtpServer2 $dns_server_2");
    push(@cfg_array,"$console_prompt,racadm config -g cfgRemoteHosts -o cfgRhostsNtpEnable 1");
  }
  # If a rackmount or blade add the following racadm commands to list
  if ($option{'m'}=~/r[0-9][1-9]|m[0-9][1-9]/) {
    push(@cfg_array,"$console_prompt,racadm config -g cfgIpmiLan -o cfgIpmiLanEnable 1");
    push(@cfg_array,"$console_prompt,racadm config -g cfgIpmiLan -o cfgIpmiLanAlertEnable 1");
    # Enabling SSH over Serial
    #push(@cfg_array,"$console_prompt,");
    #push(@cfg_array,"$console_prompt,racadm config -g cfgIpmiSerial -o cfgIpmiSerialConsoleEnable 1");
    #push(@cfg_array,"$console_prompt,racadm config -g cfgIpmiSerial -o cfgIpmiSerialBaudRate 115200");
    #push(@cfg_array,"$console_prompt,racadm config -g cfgIpmiSerial -o cfgIpmiSerialSshEnable 1");
  }
  # components common to all
  if (($option{'i'}=~/28/)&&($option{'m'}!~/m[0-9][1-9]/)) {
    push(@cfg_array,"$console_prompt,racadm setsysinfo -c chassislocation \"Building 28\"");
  }
  if ($option{'i'}=~/224/) {
    push(@cfg_array,"$console_prompt,racadm setsysinfo -c chassislocation \"Building 224\"");
  }
  push(@cfg_array,"$console_prompt,racadm config -g cfgEmailAlert -o cfgEmailAlertAddress -i $root_id $email_list");
  return;
}

# Configure iDRAC with custom settings

sub configure_idrac {
  my $record; 
  my $match; 
  my $response; 
  my $output;
  if ($option{'V'}||$option{'t'}) {
    print "Sending the following commands:\n";
  }
  $ssh_session->clear_accum();
  populate_cfg_array();
  foreach $record (@cfg_array) {
    ($match,$response)=split(',',$record);
    if ($option{'V'}||$option{'t'}) {
      print "$response\n";
    }
    if (!$option{'t'}) {
      #$ssh_session->send("\n");
      $ssh_session->expect(25,$console_prompt);
      #$output=$ssh_session->expect($pause,'-re',$match);
      $ssh_session->send("$response\n");
    }
  }
  return;
}
