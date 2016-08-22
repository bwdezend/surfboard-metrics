#!/usr/bin/perl

#use warnings;
#use strict;

use LWP::Simple;
use HTML::Entities;
use HTML::TableContentParser;
use Data::Dumper;

use IO::Socket;

my $VERBOSE = 0;

our $buff = '';
my $sock_timeout = 10;

my $buffer_size   = 8192;
my $graphite_host = 'fqdn.example.com';
my $graphite_port = 2003;

my $url  = 'http://192.168.100.1/RgConnect.asp';
my $page = get($url);

while (1) {
    &parse_surfboard_html();
    sleep(10);
}


exit 0;

sub parse_surfboard_html {
     my $date = time();
     $page =~ s/Power Level<TABLE.+TABLE>/Power Level/g;
     $page =~ s/&nbsp;/ /g;
     $page = decode_entities($page);
     
     my $tcp    = HTML::TableContentParser->new;
     my $tables = $tcp->parse($page);
     
     #print $tables;
     our $data;
     my $table_number = 0;
     
     for $t (@$tables) {
        $table_number++;
         my @channels = ();
         my $row = 0;
         my %header = undef;
         for $r ( @{ $t->{rows} } ) {
     
             #print "Row: $row\n";
             
             my $count  = 0;
             my $col_index = 0;
             my $current_channel = 0;
             for $c ( @{ $r->{cells} } ) {
                 if ( $row eq 1 ) {
                    #print "raw h: $h\n";
                     $h = lc( $c->{data} );
                     $h =~ s/\s/_/g;
                     $h =~ s/<strong>//g;
                     $h =~ s/<\/strong>//g;
                     #print "Setting header $count to $h\n";
                     $header{$count} = $h;
                 }
                 else {
                    if ($count eq 0) {
                      $current_channel = $c->{data};
                    }
     
                     $c->{data} =~ s/dBmV\n/dBmV/g;
                     $c->{data} =~ s/<BR>\n/ /g;
     
                     my $cdata = $c->{data};
                     $cdata =~ s/\s//g;
                     $cdata =~ s/dBmV//g;
                     $cdata =~ s/dB//g;
                     $cdata =~ s/Hz//g;
                     if ( $cdata =~ m/(\d+\.\d+)Msym\/sec/ ) {
                         $cdata = ( $1 * 1000000 );
                     }
     
                     #print " tn:$table_number current_channel:$current_channel header:$header{$count} [$c->{data}] \n";
                     $data->{ $table_number }->{ $current_channel }->{ $header{$count} } = $cdata;
     
                 }
                 $count++;
                 $col_index++;
             }
             $row++;
         }
     }
     
     foreach my $k1 ( sort keys %{$data} ) {
        #print "processing table: $k1\n";
         my $updown = undef;
     
     
         if ( $k1 == "2"  ) {
             $updown = 'downstream_modulation';
            foreach my $k2 ( sort keys %{ $data->{$k1} } ){
                    &send_to_graphite( "surfboard.6183.$updown."
                   . $k2 . ".snr_db  $data->{$k1}->{$k2}->{'snr'} $date\n" );
                    &send_to_graphite( "surfboard.6183.$updown."
                   . $k2 . ".corrected  $data->{$k1}->{$k2}->{'corrected'} $date\n" );
                    &send_to_graphite( "surfboard.6183.$updown."
                   . $k2 . ".uncorrectables  $data->{$k1}->{$k2}->{'uncorrectables'} $date\n" );
                    &send_to_graphite( "surfboard.6183.$updown."
                   . $k2 . ".power  $data->{$k1}->{$k2}->{'power'} $date\n" );
                   
            }
     
        }
     
         if ( $k1 ==  "3"  ) {
     
             $updown = 'upstream_modulation';
     
            foreach my $k2 ( sort keys %{ $data->{$k1} } ){
                &send_to_graphite( "surfboard.6183.$updown."
                  . $k2 . ".power $data->{$k1}->{$k2}->{'power'} $date\n" );
            }
     
         }
     
     }

}


sub send_to_graphite {
    my $buff = shift;
    return 0 if length($buff) == 0;
    my $sock = IO::Socket::INET->new(
        PeerAddr => $graphite_host,
        PeerPort => $graphite_port,
        Proto    => 'tcp',
        Timeout  => $sock_timeout
    );
    unless ($sock) {
        print "failed to connect to $graphite_host:$graphite_port\n";
        return 0;
    }
    print $sock $buff;
    close($sock);

    print "$buff";
    $buff = '';
    return 1;
}

