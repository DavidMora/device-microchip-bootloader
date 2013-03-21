use strict; # To keep Test::Perl::Critic happy, Moose does enable this too...

package Device::Microchip::Bootloader;

use Moose;
use namespace::autoclean;
use 5.012;
use autodie;

use Fcntl;
use IO::Socket::INET;
use Digest::CRC qw(crc16);
use Data::Dumper;

has firmware => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has device => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has verbose => (
    is => 'ro',
    isa => 'Int',
    default => '0',
);

use Carp qw/croak carp/;

# Ensure we read the hexfile after constructing the Bootloader object
sub BUILD {
    my $self = shift;
    $self->_read_hexfile;
}

# Program the target device
sub program {
    my $self = shift;
    
    my $connected;

    # Connect to the target device
    $connected = $self->_connect();

    return 0 if !$connected;

    # Request the info on the connected device
    $self->_write_packet("0102");
   
    # Display the target device type
    my $response = $self->_read_packet(2);

    print Dumper($response);

    return 1;
}

# Open the connection to the target device (serial port or TCP)
# depending on the target parameters that were passed
sub _connect {
    my $self = shift;

    # Open the port
    $self->_device_open();

    # Wait for the pic to respond to the magic characters
    $self->_debug(1, "Sending hello...");
    my $start = "\x0F\x0F\x0F\x0F\x0F\x0F\x0F\x0F\x0F\x0F";
    syswrite($self->{_fh}, $start, length($start));
    
    my $bytes = $self->_read_packet(10, 1);

    return $bytes;

}

# open the port to a device, be it a serial port or a socket
sub _device_open {
    my $self = shift;

    my $dev = $self->device();
    my $fh;
    my $baud = 115200;

    if ($dev =~ /\//) {
	if (-S $dev) {
	    $fh = IO::Socket::UNIX->new($dev)
		or croak("Unix domain socket connect to '$dev' failed: $!\n");
	} else {
	    require Symbol;
	    require Device::SerialPort;
	    import Device::SerialPort qw( :PARAM :STAT 0.07 );
	    $fh = Symbol::gensym();
	    my $sport = tie (*$fh, 'Device::SerialPort', $dev) or
		$self->argh("Could not tie serial port to file handle: $!\n");
	    $sport->baudrate($baud);
	    $sport->databits(8);
	    $sport->parity("none");
	    $sport->stopbits(1);
	    $sport->datatype("raw");
	    $sport->write_settings();
	    sysopen($fh, $dev, O_RDWR|O_NOCTTY|O_NDELAY)
		or croak("open of '$dev' failed: $!\n");
	    $fh->autoflush(1);
	}
    } else {
	$dev .= ':'.('10001') unless ($dev =~ /:/);
	$fh = IO::Socket::INET->new($dev)
	    or croak("TCP connect to '$dev' failed: $!\n");
    }

    $self->_debug(1, "Port opened");

    $self->{_fh} = $fh;
    return;

}

## write_serial
#   Prints data to the serial port.
#   the controller
#   Takes a string of hex characters as input (e.g. "DEADBEEF")
sub _write_packet {

    my ($self, $data) = @_;

    # Create packet for transmission
    my $string = pack("H*", $data);

    my $crc    = crc16($string);
    my $packet = $string . pack("C", $crc % 256) . pack ("C", $crc / 256);
    # byte stuffing for the control characters in the data stream
    $packet =~ s/\x05/\x05\x05/g;
    $packet =~ s/\x04/\x05\x04/g;
    $packet =~ s/\x0F/\x05\x0F/g;
    
    $packet = pack("C", 15) . $packet . pack("C", 4);

    $self->_debug(3, "Writing: " . $self->_hexdump($packet));


    # Write
    syswrite($self->{_fh}, $packet, length($packet));  

}


## read_serial(timeout)
#   Reads data from the serial port. Times out if nothing is
#   received after <timeout> seconds.
sub _read_packet {

    my ($self, $timeout, $sync) = @_;

    my @numresult;
    my $result;

    eval {
	# Set alarm
	alarm($timeout);

	# Execute receive code
	my $waiting = 1;
	$result = "";
	my $bytes;
	while ($waiting){

	    # Read reply
	    $bytes = $self->{_fh}->sysread($result, 2048, length($result));
	    # Verify we have the entire string (should end with 0x04 and no preceding 0x05)
	    $self->_debug(4, "Result is $result");
	    if ($sync && $result =~ /\x0F/) {
		$waiting = 0;
	    }
	    if (!($result =~ /\x05\x04$/) && ($result =~ /\x04$/)) {
		$waiting = 0;
	    }
	}
	
	# Clear alarm
	alarm(0);
    };

    # Check what happened in the eval loop
    if ($@) {
	if ($@ =~ /timeout/) {
	    # Oops, we had a timeout
	    croak("Timeout waiting for data from device");
	} else {
	        # Oops, we died
	    alarm(0);           # clear the still-pending alarm
	    die;                # propagate unexpected exception
	} 
	
    } 

    return 1 if ($sync);

    # We get here if the eval exited normally
    @numresult = $self->_parse_response($result);

    return @numresult;
}

## parse_response
# Decode the response from the embedded device, i.e. remove 
# protocol overhead, and return the remaining result.
sub _parse_response {
    my ($self, $input) = @_;
    
    # Verify packet structure <STX><STX><...><ETX>
    if (!(($input =~ /^\x0F/) && ($input =~ /\x04$/) && !($input =~ /\x05\x04$/))) {
	croak("Received invalid packet structure from PIC\n");
    }

    # Remove the byte stuffing
    # <DLE>
    $input =~ s/\x05\x05/\x05/g;
    # <ETX>
    $input =~ s/\x05\x04/\x04/g;
    # <STX>
    $input =~ s/\x05\x0F/\x0F/g;    
    

    # Process the received data
    my @numresult = unpack("C*", $input);
    

    # Verify the CRC
    my $crc_check = 0;

    # Skip the 2 header bytes
    if (shift(@numresult) != 15){
	croak("Header byte 1 in response from PIC != 15!");
    }

    foreach (@numresult){
	$crc_check += $_; 
#print $_ . " ";
    } 

    # TODO: check CRC
    return @numresult;

    $crc_check = $crc_check % 256;

    # If all is OK, then crc_check is 4 by now (0x04 = end of packet character).
    if ($crc_check == 4) {
	# data OK, remove trailing 4 from data
	pop(@numresult);
	# remove CRC from data
	pop(@numresult);
    } else {
	carp("Received invalid CRC in response from PIC\n");
    }
   
    return @numresult;
    
}


# Read the hexfile containing the program memory data
sub _read_hexfile {

    my $self = shift;

    open my $fh, '<', $self->{firmware};
#        or croak "Could not open firmware hex file for reading: $!";

    my $counter = 0;
    my $offset  = 0;

    while ( my $line = <$fh> ) {
        chomp($line);

        $counter++;

        # Check for end of file marker
        if ( $line =~ /^:[0-9A-F]{6}01/ ) {

            #print "End of file marker found.\n";
            last;
        }

        # Translate extended Linear Address Records
        if ( $line =~ /^:(02000004([0-9A-F]{4}))([0-9A-F]{2})/ ) {
            $offset = hex($2);
            $self->_check_crc( $1, $3, $counter );

            $self->_debug(2, "Detected HEX386 Extended Linear Address Record in hex file, using offset: $offset");

            next;
        }

        # Translate data records
        if ( $line
            =~ /^:(([0-9A-F]{2})([0-9A-F]{4})00([0-9A-F]+))([0-9A-F]{2})/ )
        {

            # $1 = everything but the CRC
            # $2 = nr of words
            # $3 = address
            # $4 = data
            # $5 = crc
            my $address = hex($3);

            # Check if we have valid CRC
            $self->_check_crc( $1, $5, $counter );

            # If CRC was valid, add it to the memory datastructure
            # Be sure to add the $offset from the Linear Address Record!
            $self->_add_to_memory( $address + $offset, $4 );

            next;
        }

        # Catch invalid records
        croak(
            $self->{firmware} . " contains invalid info on line $counter." );

    }

    close($fh);
}

# Verify the CRC of a line read from the HEX file
#   If CRC is invalid, then suggest the correct one (so you
#   don't have to calculate it yourself when doing instruction
#   level hacking :-) )
sub _check_crc {
    my ( $self, $data, $crc_in, $line_num ) = @_;

    $crc_in = hex($crc_in);

    my $string = pack( "H*", $data );
    my $crc_calc = ( 256 - unpack( "%a*", $string ) % 256 ) % 256;

    if ( $crc_calc != $crc_in ) {
        my $nice_crc = $self->_dec2hex($crc_calc);
        carp(
            "Invalid CRC in '$self->{firmware}' on line $line_num, should be 0x$nice_crc"
        );
    }

}

# Helper function converting dec2hex
sub _dec2hex {

    my ( $self, $dec, $fill ) = @_;

    my $fmt_string;

    if ( defined($fill) ) {
        $fmt_string = "%0" . $fill . "X";
    }
    else {
        $fmt_string = "%02X";
    }
    return sprintf( $fmt_string, $dec );
}

# Add an entry to the memory variable that will be used to flash the PIC
sub _add_to_memory {

    my ( $self, $address, $data_in ) = @_;

    my $index;
    my $mem_addr;

    my @data = unpack( "a4" x ( length($data_in) / 4 ), $data_in );

    # Scan the line
    for ( $index = 0; $index < scalar(@data); $index++ ) {

# Calculate the actual address ($index * 2) because we read bytes and write shorts
        $mem_addr = ( $index * 2 ) + $address;

        # And add the info if the location is not defined yet
        if ( !defined( $self->{_program}->{$mem_addr} ) ) {
            $self->{_program}->{$mem_addr}->{data} = $data[$index];
        }
        else {
            my $error
                = sprintf "Memory location 0x%X defined twice in hex file.\n",
                $mem_addr;
            croak $error;
        }
    }

}

# Displays the program memory contents in hex format on the screen
sub _print_program_memory {
    my $self = shift;

    my $counter = 0;

    foreach my $entry ( sort { $a <=> $b } keys $self->{_program} ) {
        if ( ( $counter % 8 ) == 0 ) {
            print "\n $counter\t: ";
        }
        print $self->{_program}->{$entry}->{data};
        $counter++;
    }
}

# debug
#   Debug print supporting multiple log levels
sub _debug {

    my ($self, $debuglevel, $logline) = @_;

    if ($debuglevel <= $self->verbose()) {
	say "+$debuglevel= $logline\n";
    } 
}

# Print input string of characters as hex
sub _hexdump {
    my ($self, $s) = @_;
    my $r = unpack 'H*', $s;
    $s =~ s/[^ -~]/./g;
    return $r . ' (' . $s . ')';
}
 
# Speed up the Moose object construction
__PACKAGE__->meta->make_immutable;

1;

# ABSTRACT: Bootloader host software for Microchip PIC devices

=head1 SYNOPSIS

my $loader = Device::Microchip::Bootloader->new(firmware => 'my_firmware.hex', target => '/dev/ttyUSB0');

=head1 DESCRIPTION

Host software for bootloading a HEX file to a PIC microcontroller that is programmed with the bootloader as described in Microchip AN1310.

The tool allows bootloading over serial port and over ethernet when the device is connected over a serial to ethernet adapter such as a Lantronix XPort.

=head1 METHODS

=head2 C<new(%parameters)>

This constructor returns a new Device::Microchip::Bootloader object. Supported parameters are listed below

=over

=item firmware

The hex file that is to be programmed into the target device. Upon creation of the object, the HEX file will be examined and possible errors will be flagged.

=item device

The target device where to send the firmware to. This can be either a serial port object (e.g. /dev/ttyUSB0) or a TCP socket (e.g. 192.168.1.52:10001).

=back

=head2 C<BUILD>

An internal function used by Moose to run code after the constructor. Need to document because otherwise Test::Pod::Coverage test fails


=cut
