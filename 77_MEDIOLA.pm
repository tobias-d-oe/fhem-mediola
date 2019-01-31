####################################################################################################
#
#  77_MEDIOLA.pm
#
#  (c) 2016 Tobias D. Oestreicher
#
#  
#  Connect fhem to Mediola GW 
#  inspired by 59_PROPLANTA.pm
#
#  Copyright notice
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the text file GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
#
#
#
####################################################################################################

package main;
use strict;
use warnings;
use Encode qw/from_to/;
use Encode::Detect::Detector;
use URI::Encode qw(uri_encode uri_decode);
use Time::Piece;
use HTTP::Request::Common qw(POST);
use String::Unescape qw(unescape);

no if $] >= 5.017011, warnings => 'experimental::lexical_subs','experimental::smartmatch';

my $missingModul;
eval "use LWP::UserAgent;1" or $missingModul .= "LWP::UserAgent ";
eval "use JSON;1" or $missingModul .= "JSON ";
eval "use Encode;1" or $missingModul .= "Encode ";
eval "use Data::Dumper;1" or $missingModul .= "Data::Dumper ";
eval "use XML::Simple;1" or $missingModul .= "XML::Simple";

require 'Blocking.pm';
require 'HttpUtils.pm';
use vars qw($readingFnAttributes);

use vars qw(%defs);
my $MODUL           = "MEDIOLA";
my $version         = "0.0.1";


# Declare functions
sub MEDIOLA_Log($$$);
sub MEDIOLA_Initialize($);
sub MEDIOLA_Define($$);
sub MEDIOLA_Undef($$);
sub MEDIOLA_Set($@);
sub MEDIOLA_Get($@);
sub MEDIOLA_Start($);
sub MEDIOLA_Aborted($);
sub MEDIOLA_Done($);
sub MEDIOLA_Run($);

########################################
sub MEDIOLA_Log($$$) {

    my ( $hash, $loglevel, $text ) = @_;
    my $xline       = ( caller(0) )[2];

    my $xsubroutine = ( caller(1) )[3];
    my $sub         = ( split( ':', $xsubroutine ) )[2];
    $sub =~ s/MEDIOLA_//;

    my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
    Log3 $instName, $loglevel, "$MODUL $instName: $sub.$xline " . $text;
}

###################################
sub MEDIOLA_Initialize($) {

    my ($hash) = @_;
    $hash->{DefFn}    = "MEDIOLA_Define";
    $hash->{UndefFn}  = "MEDIOLA_Undef";
    $hash->{SetFn}    = "MEDIOLA_Set";
    $hash->{GetFn}    = "MEDIOLA_Get";
    $hash->{AttrList} = "ir:00,01,02,04,08 ".
                        "rf:00,01,02,04,08 ".
			$readingFnAttributes;
   
    foreach my $d(sort keys %{$modules{MEDIOLA}{defptr}}) {
        my $hash = $modules{MEDIOLA}{defptr}{$d};
        $hash->{VERSION}      = $version;
    }
}

###################################
sub MEDIOLA_Define($$) {

    my ( $hash, $def ) = @_;
    my $name = $hash->{NAME};
    my $lang = "";
    my @a    = split( "[ \t][ \t]*", $def );
   
    return "Error: Perl moduls ".$missingModul."are missing on this system" if( $missingModul );
    #return "Wrong syntax: use define <name> MEDIOLA [IP] "  if ( int(@a) != 2 );


        $hash->{STATE}           = "Initializing";
        $hash->{IP}     = $a[2];
	$hash->{CONFIGFILE} = $a[3];
        $hash->{INTERVAL}     = "60"; 
        
        $hash->{fhem}{LOCAL}     = 0;
        $hash->{VERSION}         = $version;


        RemoveInternalTimer($hash);
 
    	$hash->{helper}{RUNNING_PID} =
        BlockingCall( 
            "MEDIOLA_Run",          # callback worker task
            $name,              # name of the device
            "MEDIOLA_Done",         # callback result method
            120,                # timeout seconds
            "MEDIOLA_Aborted",      #  callback for abortion
            $hash );            # parameter for abortion
      
        #Get first data after 12 seconds
        InternalTimer( gettimeofday() + 12, "MEDIOLA_Start", $hash, 0 );
   
    return undef;
}

#####################################
sub MEDIOLA_Undef($$) {

    my ( $hash, $arg ) = @_;

    RemoveInternalTimer( $hash );
    BlockingKill( $hash->{helper}{RUNNING_PID} ) if ( defined( $hash->{helper}{RUNNING_PID} ) );
   
    return undef;
}

####################################
sub MEDIOLA_Get($@) {

    my ( $hash, @a ) = @_;
    my $name    = $hash->{NAME};
    my $usage   = "Unknown argument $a[1], choose one of learncode:noArg ";
    my $noarg   = "No Argument given for current command";

    return $usage if ( $a[1] eq "?" );
    return $noarg if ( @a < 1 );

    my $cmd = lc( $a[1] );
    MEDIOLA_Log $hash, 5, "get command: " . $cmd;
    if ( "$cmd" eq "learncode" ) {

        my $ua = new LWP::UserAgent();
	my $url = 'http://'.$hash->{IP}.'/command?XC_FNC=Learn';
	MEDIOLA_Log $hash, 1, "learn command: " . $url;
	my $httpresp = $ua->get($url);
	MEDIOLA_Log $hash, 1, $httpresp->content;
	return "MediolaGW not reachable, please verify configuration and connection" unless $httpresp->is_success;; # $httpresp->content;
	return $httpresp->content;	       #
    
    } 



}



#####################################
sub MEDIOLA_Set($@) {

    my ( $hash, @a ) = @_;
    my $name    = $hash->{NAME};
    my $MEDIOLA_ir;
    my $MEDIOLA_rf;

    my $json;
    {
        local $/; #Enable 'slurp' mode
        open my $fh, "<", $hash->{CONFIGFILE};
        $json = <$fh>;
        close $fh;
    }
    
    my $perl_scalar = JSON->new->utf8->decode($json);
    my $keys = $perl_scalar->{'remote'};
    my $out="";
    my $usage   = "Unknown argument $a[1], choose one of ";
    for my $val (@{$keys}) {
    	$out .= $val->{'key'}." -> ".$val->{'code'}."\n";
    	$usage .= $val->{'key'}.":noArg ";
    }
    	
    my $noarg   = "No Code given for transmit";
    
    return $usage if ( $a[1] eq "?" );
    return $noarg if ( @a < 2 );
    
    
    
    my $cmd = "";
    for my $val (@{$keys}) {
    	if ( $val->{'key'} eq $a[1] ) {
    	    $cmd = $val->{'code'};
    	}
    }

    my $attrir     = AttrVal( $name, 'ir','');
    my $attrrf     = AttrVal( $name, 'rf','');

    if ($attrir eq "") {
	$MEDIOLA_ir = "00";
    } else {
        $MEDIOLA_ir = $attrir;
    }
    if ($attrrf eq "") {
	$MEDIOLA_rf = "00";
    } else {
        $MEDIOLA_rf = $attrrf;
    }

    my $ua = new LWP::UserAgent();
    my $url = 'http://'.$hash->{IP}.'/command?XC_FNC=Send2&code='.$cmd.'&ir='.$MEDIOLA_ir.'&rf='.$MEDIOLA_rf;
    MEDIOLA_Log $hash, 3, "set url: " . $url;
    my $httpresp = $ua->get($url);
    MEDIOLA_Log $hash, 3, $httpresp->content;
    MEDIOLA_Log $hash, 3, $httpresp->is_success;
    readingsSingleUpdate($hash, "lastcmd", $a[1], 1);
    readingsSingleUpdate($hash, "state", "ERROR", 1) unless $httpresp->is_success;
    return "MediolaGW not reachable, please verify configuration and connection" unless $httpresp->is_success;
    #return $httpresp->content;
    readingsSingleUpdate($hash, "state", "OK", 1);
    return "OK";
}




#####################################
sub MEDIOLA_Start($) {

    my ($hash) = @_;
    my $name   = $hash->{NAME};
   
    return unless (defined($hash->{NAME}));
   
    if(!$hash->{fhem}{LOCAL} && $hash->{INTERVAL} > 0) {        # set up timer if automatically call
    
        RemoveInternalTimer( $hash );
        InternalTimer(gettimeofday() + $hash->{INTERVAL}, "MEDIOLA_Start", $hash, 1 );  
        return undef if( AttrVal($name, "disable", 0 ) == 1 );
    }

  
}

#####################################
sub MEDIOLA_Aborted($) {

    my ($hash) = @_;
    delete( $hash->{helper}{RUNNING_PID} );
}

#####################################
# asyncronous callback by blocking
sub MEDIOLA_Done($) {

    my ($string) = @_;
    return unless ( defined($string) );
   
    # all term are separated by "|" , the first is the name of the instance
    my ( $name, %values ) = split( "\\|", $string );
    my $hash = $defs{$name};
    return unless ( defined($hash->{NAME}) );
   
    # delete the marker for RUNNING_PID process
    delete( $hash->{helper}{RUNNING_PID} );  

    # daten speichern
    readingsBeginUpdate($hash);
    my $newstate = "Initialized";
    my $is_online = 0;
    while (my ($rName, $rValue) = each(%values) ) {
	if ($rName eq "hwv") { $is_online = 1; }
        readingsBulkUpdate( $hash, $rName, $rValue );
        MEDIOLA_Log $hash, 5, "reading:$rName value:$rValue";
 
    }
    if ( $is_online == 1 ) {
        readingsBulkUpdate( $hash, "state", $newstate ); 
    } else {
        readingsBulkUpdate( $hash, "state", "Offline" ); 
    }
    readingsEndUpdate( $hash, 1 );
}


#####################################
sub MEDIOLA_Run($) {

    my ($name) = @_;
    my $ptext=$name;
    my $is_reachable=1;
    return unless ( defined($name) );
   
    my $hash = $defs{$name};
    return unless (defined($hash->{NAME}));
    
    my $readingStartTime = time();


    my $message;
    MEDIOLA_Log $hash, 1, "Start Run!";
    my $con = IO::Socket::INET->new(Proto=>"udp",LocalPort=>34601,PeerPort=>1901,PeerAddr=> $hash->{IP})
      or $is_reachable=0;

    if ( $is_reachable == 1 ) {
        $con->send("GET");
        $con->recv(my $datagram,300);
        
        close($con);
        MEDIOLA_Log $hash, 5, length($datagram);
        foreach (split(/\n/,$datagram)) {
            my ($fldname, $fldvalue) = (split(/\:/,$_))[0,1];
            MEDIOLA_Log $hash, 5, "Current:".$fldname;
            if (index("$fldname", "DHCP") != -1) {
                $message .= lc "DHCP|";
        	    $message .= "$fldvalue|";
                MEDIOLA_Log $hash, 5, "Set(DHCP):".$fldname." to: ".$fldvalue;
            } else {
                MEDIOLA_Log $hash, 5, "Set:".$fldname." to: ".$fldvalue;
                $message .= lc "$fldname|";
                $message .= "$fldvalue|";
            }
        }
        
	    $hash->{STATE} = "Online";
    } else {
	    $hash->{STATE} = "Offline";
    }
    $message .= "durationFetchReadings|";
    $message .= sprintf "%.2f",  time() - $readingStartTime;
    
    MEDIOLA_Log $hash, 5, "Done fetching data";
    MEDIOLA_Log $hash, 5, "Will return : "."$name|$message" ;
    return "$name|$message" ;
}










##################################### 
1;




















=pod

=item device
=item summary       integrate simple usage of MediolaGW

=begin html

<a name="MEDIOLA"></a>
<h3>MEDIOLA</h3>
<ul>
   <a name="MEDIOLAdefine"></a>
   This modul can be used with a Mediola Gateway to send and learn ir/rf codes.
   <br/>
   <br/><br/>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;Name&gt; MEDIOLA [IP] [ConfigFile]</code>
      <br><br><br>
      Example:
      <br>
      <code>
        define TVSchlafzimmer MEDIOLA 192.168.0.35 mediola/tvsz.json<br>
        attr TVSchlafzimmer ir 00<br>
        attr TVSchlafzimmer rf 01<br>
      </code>
      <br>&nbsp;

      <li><code>[IP]</code>
         <br>
         Set the IP Address of the Mediola GW<br/>
      </li><br>

      <li><code>[ConfigFile]</code>
         <br>
         Set the Path to a Configurationfile in JSON format.<br/>
         As example:<br>
         <textarea rows="10" cols="50">
{ "remote": [
	{ "key" : "power", 
          "code": "19082600000100260608B6044D00890089008901A20089277A08B6022D00895DA90001010201010101010202010202020202010101020101010102020201020202020304050405" },
	{ "key" : "volmute",
          "code":  "19082600000100260608B9045100890088008901A30089277A08B9022B00895DA90001010201010101010202010202020202020101020101010101020201020202020304050405" }
	    ]
}
	 </textarea>
      </li><br>


      <br>&nbsp;


   </ul>
   <br>

   <a name="MEDIOLAget"></a>
   <b>Get</b>
   <ul>
      <br>
      <li><code>get &lt;name&gt; learncode</code>
         <br>
         after execute get function hold your remote appx. 30 cm next to the gateway and press the button you want to learn.
      </li><br>
   </ul>  
  
   <br>



   <a name="MEDIOLAset"></a>
   <b>Set</b>
   <ul>
      <br>
      <li><code>set &lt;name&gt; <key></code>
         <br>
         Executes a command set within the [ConfigFile]. You can learn the code with get <MediolaDevice> learncode.
      </li><br>
   </ul>  
  
   <br>




=end html


=begin html_DE

<a name="MEDIOLA"></a>
<h3>MEDIOLA</h3>
<ul>
   <a name="MEDIOLAdefine"></a>
   Dieses Modul kann benutzt werden um mit einem Mediola Gateway IR/RF Codes zu senden und zu lernen. 
   <br/>
   <br/><br/>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;Name&gt; MEDIOLA [IP] [ConfigFile]</code>
      <br><br><br>
      Beispiel
      <br>
      <code>
        define TVSchlafzimmer MEDIOLA 192.168.0.35 mediola/tvsz.json<br>
        attr TVSchlafzimmer ir 00<br>
        attr TVSchlafzimmer rf 01<br>
      </code>
      <br>&nbsp;

      <li><code>[IP]</code>
         <br>
         Set the IP Address of the Mediola GW<br/>
      </li><br>

      <li><code>[ConfigFile]</code>
         <br>
         Der Pfad zur Konfigurationsdatei im JSON Format für die Fernbedienung.<br/>
         Als Beispiel:<br>
         <textarea rows="10" cols="50">
{ "remote": [
	{ "key" : "power", 
          "code": "19082600000100260608B6044D00890089008901A20089277A08B6022D00895DA90001010201010101010202010202020202010101020101010102020201020202020304050405" },
	{ "key" : "volmute",
          "code":  "19082600000100260608B9045100890088008901A30089277A08B9022B00895DA90001010201010101010202010202020202020101020101010101020201020202020304050405" }
	    ]
}
	 </textarea>
      </li><br>


      <br>&nbsp;


   </ul>
   <br>

   <a name="MEDIOLAget"></a>
   <b>Get</b>
   <ul>
      <br>
      <li><code>get &lt;name&gt; learncode</code>
         <br>
         nachdem learncode ausgeführt wurde muss im Abstand von ca. 30 cm vom Mediola Gateway die Taste der zu lernenden Fernbedienung gedrückt werden. Daraufhin wird der empfangene Code angezeigt. Dieser kann dann in das [ConfigFile] übernommen werden.
      </li><br>
   </ul>  
  
   <br>



   <a name="MEDIOLAset"></a>
   <b>Set</b>
   <ul>
      <br>
      <li><code>set &lt;name&gt; <key></code>
         <br>
         Senden einer in dem [ConfigFile] definierten Fernbedienungs Taste.
      </li><br>
   </ul>  
  
   <br>




=end html_DE


=cut
