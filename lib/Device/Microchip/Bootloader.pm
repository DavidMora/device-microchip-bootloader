use strict;
use warnings;
use 5.012;
use autodie;

package Device::Microchip::Bootloader;

use Varp qw/croak carp/;

# ABSTRACT: Bootloader host software for Microchip PIC devices

=head1 SYNOPSIS

my $loader = Device::Microchip::Bootloader->new(firmware => 'my_firmware.hex', target => '/dev/ttyUSB0');

=head1 DESCRIPTION

Host software for bootloading a HEX file to a PIC microcontroller that is programmed with the bootloader as described in Microchip AN1310.

The tool allows bootloading over serial port and over ethernet when the device is connected over a serial to ethernet adapter such as a Lantronix XPort.

=method C<new(%parameters)>

This constructor returns a new Device::Microchip::Bootloader object. SUpported parameters are listed below

=over

=item firmware

The hex file that is to be programmed into the target device. Upon creation of the object, the HEX file will be examined and possible errors will be flagged.

=item device

The target device where to send the firmware to. This can be either a serial port object (e.g. /dev/ttyUSB0) or a TCP socket (e.g. 192.168.1.52:10001). 

=back

=cut

sub new {
    my ($pkg, %p) = @_;

    my $self = bless {
	_program = {}, # Internal hash to store the contents of the program memory
	%p
    }, $pkg;

    if (!defined $self->{firmware}) {
	croak("Please pass a firmware HEX file for reading");
    }

    if (!defined $self->{device}) {
	croak("Please pass a target device to send the firmware to");
    }

    return $self;
}



1;
