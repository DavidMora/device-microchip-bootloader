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
    my $loader = Device::Microchip::Bootloader->new( firmware => '../t/stim/test.hex', device => '/dev/cu.usbserial-00004006', verbose => 3);
#    my $loader = Device::Microchip::Bootloader->new( firmware => '../t/stim/test.hex');
	$loader->connect_target();
    #$loader->_print_program_memory();
    my $data = $loader->read_eeprom(0, 4);
	say "Read from EEPROM: $data";
	$data = $loader->read_flash(0, 8);
	say "Read from FLASH:  $data";
	$data = $loader->read_flash(0xFC00, 100);
	say "Read from FLASH:  $data";
	# Erase a page
	$data = $loader->erase_flash(0x1FFE, 2);
	say "Erased flash: $data";
	# Write a page
	$data = $loader->write_flash(0x1000, "0201000000000000000000000000000000000000020100000000000000000000000000000000000002010000000000000000000000000000000000000201000000000000000000000000000000000000020100000000000000000000000000000000000002010000000000000000000000000000000000001111222233334444");	
	say "Wrote flash: $data";
	
	

#} else {
#    die
#"Please pass the folder with the files that need to be parsed as command line option";
#}
