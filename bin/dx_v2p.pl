# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Copyright (c) 2015,2016 by Delphix. All rights reserved.
#
# Program Name : dx_v2p.pl
# Description  : Provision a VDB
# Author       : Marcin Przepiorowski
# Created      : 22 Apr 2015 (v2.0.0)
#



use strict;
use warnings;
use JSON;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev); #avoids conflicts with ex host and help
use File::Basename;
use Pod::Usage;
use FindBin;
use Data::Dumper;

my $abspath = $FindBin::Bin;

use lib '../lib';
use Databases;
use Engine;
use Jobs_obj;
use Group_obj;
use Toolkit_helpers;
use FileMap;

my $version = $Toolkit_helpers::version;

my $timestamp = 'LATEST_SNAPSHOT';

GetOptions(
  'help|?' => \(my $help), 
  'd|engine=s' => \(my $dx_host), 
  'sourcename=s' => \(my $sourcename),
  'srcgroup=s' => \(my $srcgroup),  
  'dbname=s'  => \(my $dbname), 
  'instname=s'  => \(my $instname), 
  'uniqname=s'  => \(my $uniqname), 
  'environment=s' => \(my $environment), 
  'type=s' => \(my $type),  
  'envinst=s' => \(my $envinst),
  'template=s' => \(my $template),
  'mapfile=s' =>\(my $map_file),
  'targetDirectory=s' => \(my $targetDirectory),
  'archiveDirectory=s' => \(my $archiveDirectory),
  'dataDirectory=s' => \(my $dataDirectory),
  'externalDirectory=s' => \(my $externalDirectory),
  'scriptDirectory=s' => \(my $scriptDirectory),
  'tempDirectory=s' => \(my $tempDirectory),
  'timestamp=s' => \($timestamp),
  'dever=s' => \(my $dever),
  'debug:n' => \(my $debug), 
  'all' => (\my $all),
  'version' => \(my $print_version)
);



pod2usage(-verbose => 2,  -input=>\*DATA) && exit if $help;
die  "$version\n" if $print_version;   


my $engine_obj = new Engine ($dever, $debug);
my $path = $FindBin::Bin;
my $config_file = $path . '/dxtools.conf';

$engine_obj->load_config($config_file);


if (defined($all) && defined($dx_host)) {
  print "Option all (-all) and engine (-d|engine) are mutually exclusive \n";
  pod2usage(-verbose => 1,  -input=>\*DATA);
  exit (1);
}

if ( ! ( defined($type) && defined($sourcename) && defined($targetDirectory) && defined($dbname) && defined($environment) && defined($timestamp) && defined($envinst)  ) ) {
  print "Options -type, -sourcename, -targetDirectory, -dbname, -environment, -timestamp and -envinst are required. \n";
  pod2usage(-verbose => 1,  -input=>\*DATA);
  exit (1);
}

if ( ! ( ( $type eq 'oracle') || ( $type eq 'mssql') ) )  {
  print "Option -type has invalid parameter - $type \n";
  pod2usage(-verbose => 1,  -input=>\*DATA);
  exit (1);
}


# this array will have all engines to go through (if -d is specified it will be only one engine)
my $engine_list = Toolkit_helpers::get_engine_list($all, $dx_host, $engine_obj); 

my $ret = 0;

for my $engine ( sort (@{$engine_list}) ) {
  # main loop for all work
  if ($engine_obj->dlpx_connect($engine)) {
    print "Can't connect to Dephix Engine $dx_host\n\n";
    next;
  };

  my $db;
  my $jobno;

  my $databases = new Databases($engine_obj,$debug);
  my $groups = new Group_obj($engine_obj, $debug);

  my $source_ref = Toolkit_helpers::get_dblist_from_filter(undef, $srcgroup, undef, $sourcename, $databases, $groups, undef, undef, undef, undef, $debug);

  if (!defined($source_ref)) {
    print "Source database not found.\n";
    $ret = $ret + 1;
    next;
  }

  if (scalar(@{$source_ref})>1) {
    print "Source database not unique defined.\n";
    $ret = $ret + 1;
    next;
  } elsif (scalar(@{$source_ref}) eq 0) {
    print "Source database not found.\n";
    $ret = $ret + 1;
    next;
  }

  my $source = ($databases->getDB($source_ref->[0]));


  if ( $type eq 'oracle' ) {
    $db = new OracleVDB_obj($engine_obj,$debug);
    if ( defined($template) ) {
      if ( $db->setTemplate($template) ) {
        print  "Template $template not found. V2P process won't be created\n";
        exit(1);
      }  
    }

    if ( $db->setSource($source) ) {
      print "Problem with setting source. V2P won't be created.\n";
      exit(1);
    }

    if ( $db->setTimestamp($timestamp) ) {
      print "Problem with setting timestamp $timestamp. V2P process won't be started.\n";
      exit(1);
    }

    if ( defined($map_file) ) {
      my $filemap_obj = new FileMap($engine_obj,$debug);
      $filemap_obj->loadMapFile($map_file);
      $filemap_obj->setSource($sourcename);
      if ($filemap_obj->validate()) {
        die ("Problem with mapping file. V2P process won't be created.")
      }

      $db->setMapFileV2P($filemap_obj->GetMapping_rule());

    }

    if ($db->setFileSystemLayout($targetDirectory,$archiveDirectory,$dataDirectory,$externalDirectory,$scriptDirectory,$tempDirectory)) {
      print "Problem with export file system layout. Is targetDiretory set ?\n";
      exit(1);
    }

    $db->setName($dbname,$dbname);
    $jobno = $db->v2pSI($environment,$envinst);



  } 
  elsif ($type eq 'mssql') {
    $db = new MSSQLVDB_obj($engine_obj,$debug);
    $db->setName($dbname, $dbname);

    if ( $db->setSource($source) )  {
      print "Problem with setting source $sourcename. VDB won't be created.\n";
      exit(1);
    }


    $db->setTimestamp($timestamp);
    if ( $db->setFileSystemLayout($targetDirectory,$archiveDirectory,$dataDirectory,$externalDirectory,$scriptDirectory,$tempDirectory) ) {
      print "Problem with export file system layout. Is targetDiretory and dataDirectory set ?\n";
      exit(1);
    }
    $jobno = $db->v2p($environment,$envinst);
  } 

  $ret = $ret + Toolkit_helpers::waitForJob($engine_obj, $jobno, "V2P finished.","Problem with V2P process");
  
}


__DATA__

exit $ret;

=head1 SYNOPSIS

 dx_v2p.pl [ -engine|d <delphix identifier> | -all ]  -sourcename src_name  -dbname db_name -environment environment_name -type oracle|mssql -envinst OracleHome/MSSQLinstance
 -targetDirectory target_directory 
 [-timestamp LATEST_SNAPSHOT|LATEST_POINT|time_stamp]
 [-template template_name] [-mapfile mapping_file]  [-instname SID] [-uniqname db_unique_name] [-archiveDirectory arch_directory] [-dataDirectory data_dir]
 [-externalDirectory external_dir] [-tempDirectory temp_dir]
 [-help] [-debug]


=head1 DESCRIPTION

Run virtual to physical process of database specified by sourcename into specified environment

=head1 ARGUMENTS

=head2 Delphix Engine selection - if not specified a default host(s) from dxtools.conf will be used.

=over 10

=item B<-engine|d>
Specify Delphix Engine name from dxtools.conf file

=item B<-all>
Display databases on all Delphix appliance

=back

=head2 V2P arguments

=over 11

=item B<-type>
Type (oracle|mssql)

=item B<-sourcename>
dSource/VDB Name

=item B<-targetDirectory>
Target directory 

=item B<-dbname>
Target database name

=item B<-timestamp>
Time stamp for export format (YYYY-MM-DD HH24:MI:SS) or LATEST_POINT or LATEST_SNAPSHOT
Default is LATEST_SNAPSHOT

=item B<-environment>
Target environment name

=item B<-envinst>
Target environment Oracle Home or MS SQL server instance

=item B<-template>
Target VDB template name (for Oracle)

=item B<-mapfile>
Target VDB mapping file (for Oracle)

=item B<-instname>
Target VDB instance name (for Oracle)

=item B<-uniqname>
Target VDB db_unique_name (for Oracle)

=item B<-archiveDirectory>
Archive log directory

=item B<-dataDirectory>
Datafiles directory

=item B<-externalDirectory>
External directory

=item B<-temp>
Temp directory

=back


=head1 OPTIONS

=over 2

=item B<-help>          
Print this screen

=item B<-debug>
Turn on debugging

=back



=cut



