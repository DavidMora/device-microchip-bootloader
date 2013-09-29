#!/usr/bin/perl
#
# Copyright (C) 2013 by Lieven Hollevoet

# This test verifies the ploader script in bin

use strict;

use Test::More;
use Test::Requires qw/Test::SharedFork/;
use Test::SharedFork;
use IO::Select;
use IO::Socket::INET;
use Capture::Tiny qw/tee/;


BEGIN { use_ok('Device::Microchip::Bootloader'); }

my $tcp = IO::Socket::INET->new(
    Listen    => 5,
    Proto     => 'tcp',
    LocalAddr => '127.0.0.1',
    LocalPort => 0
) or plan skip_all => "Failed to open TCP server on loopback address: $!";
my $tcp_port = $tcp->sockport;

my $pid = fork();

# Make a TCP test server in a spearate thread and connect to it with the test script from the parent thread
if ( $pid == 0 ) {

    # child
    my $sel = IO::Select->new($tcp);
    $sel->can_read( 10 ) or die;
    my $client = $tcp->accept;
    ok $client, 'client accepted';
    $sel = IO::Select->new($client);
    $sel->can_read( 10  ) or die;
    my ($buf, $bytes, $resp);

    # Handle bootloader info request
    $bytes = sysread $client, $buf, 2048;
    is $bytes, 5, 'sync packet length';
    is $buf, "\x0F\x00\x00\x00\x04", "Got bootloader info request";
    $resp = "\x0F\x00\x00\x05\x05\x01\xFF\x84\x01\x02\x03\x00\x31\x42\x04";
    syswrite $client, $resp, length($resp);

    # Handle PIC version request
    $bytes = sysread $client, $buf, 2048;
    is $bytes, 11, 'PIC device packet length';
    is $buf, "\x0F\x01\xFE\xFF\x3F\x00\x02\x00\xB4\x6D\x04",
        "Got PIC type request";
    $resp = "\x0F\x71\x02\x00\x5A\x89\x04";
    syswrite $client, $resp, length($resp);

}
elsif ($pid) {
    
    #parent
    my ($stdout, $stderr) = tee { system($^X, "bin/ploader.pl", "-d127.0.0.1" . ":" . $tcp_port) };
    #is ($loader->program, 1, 'Programming over TCP done');
    is $stderr, "", "No errors encountered";
    is $stdout, "", "Expected stdout";
    
    waitpid $pid, 0;
    done_testing();
}
else {
    die $!;
}
