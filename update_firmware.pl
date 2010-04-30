#!/usr/bin/perl 
use strict;
use warnings;
use Getopt::Long;
# SNMP Requirement
use Net::SNMP qw( oid_lex_sort oid_context_match INTEGER OCTET_STRING IPADDRESS);;



sub help () {
    print   "Usage: $0 [options]\n\nOptions:\n",
            "   --ip=IP                     modem IP address ( 10 dot )\n",
            "   --community=COMMUNITY       SNMP Community String\n",
            "   --version=VERSION           SNMP Version ( default 2c )\n",
            "   --firmware=FIRMWARE         Cable Modem Firmware Name\n",
            "   --tftp_server=TFTP_SERVER   TFTP Server IP ( default 10.0.1.1)\n",
            "   --action=ACTION             CM Action ( default 2 )\n",
            "   --query                     Query the Modem Values\n";
    exit;    
} # END of the help


sub snmp_set {
    my ( $snmp, $oid, $value, $asn, $reps ) = @_;
    if( ! defined( $reps ) ) { $reps = 2048 };
    
    my $result = $snmp->set_request( 
        -varbindlist    => [$oid, $asn, $value]
    );
    
    if( ! defined( $result ) ) {
        printf("Error: %s\n", $snmp->error() );
        return undef;
    }
    
    return $result;

}

sub snmp_query {
    my ( $snmp, $oid, $reps ) = @_;
    if( ! defined $reps ) { $reps = 2048 };
    
    my $result = $snmp->get_request(
        -varbindlist    => [$oid]
    );
    
    if( ! defined( $result ) ) {
        printf("Error: %s\n", $snmp->error() );
        return undef;
    }
    
    return $result;
    
}


sub walker {
    my ( $snmp, $oid_start, $reps ) = @_;
    if( ! defined $reps ) { $reps = 2048 };
    my $next = $oid_start;
    my $results = {};
    
    loop:
    while( defined( $snmp->get_bulk_request( -maxrepetitions    => $reps,
                                             -varbindlist       => [$next] ) || die $snmp->error() ) ) 
    {

        my @oids = oid_lex_sort( keys( %{$snmp->var_bind_list} ) );
                                                         
        for my $oid ( @oids ) {
            # Skip to end if we don't have a match.
    		last loop unless ( oid_context_match( $oid_start, $oid ) );

    		# Push these into a hash.
    		$$results{$oid} = $snmp->var_bind_list->{$oid};

    		# Make sure we have not hit the end of the MIB
    		last loop if ( $snmp->var_bind_list->{$oid} eq 'endOfMibView' );
        }
    
        $next = pop( @oids );
    }
    
    return( $results );
}

eval {
    
    my @oids = (
        {oid    => '1.3.6.1.2.1.69.1.3.1.0', asn   => IPADDRESS,    name    => 'tftp_server' },
        {oid    => '1.3.6.1.2.1.69.1.3.2.0', asn   => OCTET_STRING, name    => 'firmware' },
        {oid    => '1.3.6.1.2.1.69.1.3.3.0', asn   => INTEGER,      name    => 'action' }
        );

    my @action_values = (
        1   => "Update Now",
        2   => "Update On Boot",
        3   => "Disable Updates",
        );


    my $opt = {
            'ip'            => '10.231.202.227',
            'community'     => 'public',
            'version'       => '2c',
            'firmware'      => 'SB5100MoD104aa.bin',
            'tftp_server'   => '10.0.1.1',
            'action'        => '2'
    };
    
    GetOptions(
        'ip=s'          => \$$opt{ip},
        'community=s'   => \$$opt{community},
        'version=s'     => \$$opt{version},
        'firmware=s'    => \$$opt{firmware},
        'tftp_server=s' => \$$opt{tftp_server},
        'action=s'      => \$$opt{action},
        'query'         => \$$opt{query},
        'help'          => sub { help() },
    );
    
    my $value;

    if( $$opt{'ip'} !~ /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/ ) { die( printf("Error: %s is not a valid IP\n", $$opt{'ip'} ) ) }

    if( $$opt{'tftp_server'} !~ /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/ ) { die( printf("Error: %s is not a valid IP\n", $$opt{'tftp_server'} ) ) }


    # Initial our SNMP session
    my ( $snmp, $error ) = Net::SNMP->session( -hostname    => $$opt{ip},
                                               -community   => $$opt{community},
                                               -version     => $$opt{version},
                                               -maxmsgsize  => 500 );
                                               
    eval {
        
        if( $$opt{'query'} ) {
            printf("Information for host - %s\n", $$opt{'ip'} );
        }
        
        for ( my $i=0; $i < scalar( @oids ); $i++ ) {

            if( $oids[$i]{'asn'} eq IPADDRESS ) {
                $value = $$opt{'tftp_server'};
            }
            if( $oids[$i]{'asn'} eq OCTET_STRING ) {
                $value = $$opt{'firmware'};
            }
            if( $oids[$i]{'asn'} eq INTEGER ) {
                $value = $$opt{'action'};
            }

            my $result = snmp_set( $snmp, $oids[$i]{'oid'}, $value, $oids[$i]{'asn'});

            if( ! defined( $result ) ) {
                printf("Error: %s\n", $snmp->error() );
                die 1;
            }
            if( $$opt{'query'} ) {
                my $cur_val = snmp_query( $snmp, $oids[$i]{'oid'} );
                                
                if( ! defined( $cur_val ) ) {
                    printf("Error - Unable to query: %s", $snmp->error() );
                }
                else {
                    printf("Value for %s is %s\n", $oids[$i]{'name'}, $cur_val->{ $oids[$i]{'oid'} } );
                }
            }
        }
        
        $snmp->close;
    };
    
    if($@) {
        printf("Error: %s\n", $@);
    }
};

print "Error: $@\n" if ( $@ );