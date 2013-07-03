#! /usr/bin/perl -w

use strict;
use warnings;
use 5.012;
use autodie;
use Device::Microchip::Bootloader;

# ABSTRACT: Bootloader for Microchip PIC devices
# PODNAME: ploader.pl


#if ( defined $ARGV[0] ) {

    # Create the object
    my $loader = Device::Microchip::Bootloader->new( firmware => '../t/stim/test.hex', device => '/dev/cu.usbserial-00003004', verbose => 0);
#    my $loader = Device::Microchip::Bootloader->new( firmware => '../t/stim/test.hex');
	$loader->connect_target();
    #$loader->_print_program_memory();
    my $data = $loader->read_eeprom(0, 4);
	say "Read from EEPROM: $data";
	$data = $loader->read_flash(0, 8);
	say "Read from FLASH:  $data";
	$data = $loader->read_flash(0xFC00, 100);
	say "Read from FLASH:  $data";
	

#} else {
#    die
#"Please pass the folder with the files that need to be parsed as command line option";
#}
