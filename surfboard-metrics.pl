#!/usr/bin/perl

use warnings;
use strict;

use LWP::Simple;
use HTML::Entities;
use HTML::TableContentParser;
use Data::Dumper;
use IO::Socket;

my $VERBOSE = 0;

my $date = time();

our $buff = '';
my $sock_timeout = 10;

my $buffer_size   = 8192;
my $graphite_host = '';

unless ($graphite_host){
	die "You must specifiy a graphite host on line 20!\n";
}

my $graphite_port = 2003;

my $url  = 'http://192.168.100.1/cmSignalData.htm';
my $page = get($url);

$page =~ s/Power Level<TABLE.+TABLE>/Power Level/g;
$page =~ s/&nbsp;/ /g;
$page = decode_entities($page);

my $tcp    = HTML::TableContentParser->new;
my $tables = $tcp->parse($page);

our $data;

for my $t (@$tables) {
    my @channels = ();
    for my $r ( @{ $t->{rows} } ) {

        my $count  = 0;
        my $header = undef;
        for my $c ( @{ $r->{cells} } ) {
            if ( $count eq 0 ) {
                $header = lc( $c->{data} );
                $header =~ s/\s/_/g;
            }
            else {
                if ( $header =~ m/channel/ ) {
                    my $channel = $c->{data};
                    $channel =~ s/\s//g;
                    push( @channels, $channel );
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

                $data->{ $channels[ $count - 1 ] }->{$header} = $cdata;

            }
            $count++;
        }
    }
}

foreach my $k1 ( %{$data} ) {
    if ( $data->{$k1}->{'upstream_modulation'} ) {
        &send_to_graphite( "surfboard.6121.upstream."
              . $data->{$k1}{'channel_id'}
              . ".frequency $data->{$k1}{'frequency'} $date\n" );
        &send_to_graphite( "surfboard.6121.upstream."
              . $data->{$k1}{'channel_id'}
              . ".dBmV $data->{$k1}{'power_level'} $date\n" );
        &send_to_graphite( "surfboard.6121.upstream."
              . $data->{$k1}{'channel_id'}
              . ".ranging_service_id $data->{$k1}{'ranging_service_id'} $date\n" );
        &send_to_graphite( "surfboard.6121.upstream."
              . $data->{$k1}{'channel_id'}
              . ".ranging_status $data->{$k1}{'ranging_status_'} $date\n" );
        &send_to_graphite( "surfboard.6121.upstream."
              . $data->{$k1}{'channel_id'}
              . ".symbol_rate $data->{$k1}{'symbol_rate'} $date\n" );

    }
    if ( $data->{$k1}{'downstream_modulation'} ) {
        &send_to_graphite( "surfboard.6121.downstream."
              . $data->{$k1}{'channel_id'}
              . ".dBmV $data->{$k1}{'power_level'} $date\n" );
        &send_to_graphite( "surfboard.6121.downstream."
              . $data->{$k1}{'channel_id'}
              . ".total_uncorrectable_codewords $data->{$k1}{'total_uncorrectable_codewords'} $date\n"
        );
        &send_to_graphite( "surfboard.6121.downstream."
              . $data->{$k1}{'channel_id'}
              . ".snr_db  $data->{$k1}{'signal_to_noise_ratio'} $date\n" );
        &send_to_graphite( "surfboard.6121.downstream."
              . $data->{$k1}{'channel_id'}
              . ".frequency $data->{$k1}{'frequency'} $date\n" );
        &send_to_graphite( "surfboard.6121.downstream."
              . $data->{$k1}{'channel_id'}
              . ".total_unerrored_codewords $data->{$k1}{'total_unerrored_codewords'} $date\n"
        );
        &send_to_graphite( "surfboard.6121.downstream."
              . $data->{$k1}{'channel_id'}
              . ".total_correctable_codewords $data->{$k1}{'total_correctable_codewords'} $date\n"
        );

    }
}

exit 0;

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

    print "$buff" if ($VERBOSE);
    $buff = '';
    return 1;
}


