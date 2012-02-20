#!/usr/bin/perl -w
use strict;

use vars qw($error_msg $debug);
use Mtik;

$Mtik::debug = 2;

###############################################################################
######
###### Examples of how to drive the Mtik module.
######
###### Some useful routines for manipulating wireless ACL's, i.e. using commands
###### from:
######
###### /interface wireless access-list
######

sub mtik_wireless_access_get_macs
{
    # get a list of all wireless access items.  We're specifying 'mac-address'
    # as the key, so the resulting associative array will be indexed by mac.
    # If we left the second argument off, it would index by the Mtik internal ID
    my(%wireless_macs) = Mtik::get_by_key('/interface/wireless/access-list/print','mac-address');
    if ($Mtik::error_msg eq '')
    {
        # so now we have a two domensional associative array, first keyed
        # by the MAC, then by attributes.  Print it out if in debug.
        if ($Mtik::debug > 5)
        {
            foreach my $mac (keys (%wireless_macs))
            {
                print "MAC: $mac\n";
                foreach my $attr (keys (%{$wireless_macs{$mac}}))
                {
                    print "   $attr: $wireless_macs{$mac}{$attr}\n";
                }
            }
        }
    }
    # we return the array rather than setting a global, as we pretty much always
    # want to call this routine prior to doing anything with ACL's, even if it
    # has already been called, in case someone else has changed the ACL list
    # underneath us.
    return %wireless_macs;
}

sub mtik_wireless_access_mac_exists
{
    my($mac) = shift;
    # we need to load the access list every time we check, because other
    # people could be actively making changes
    my(%wireless_macs) = &mtik_wireless_access_get_macs();
    if ($Mtik::error_msg)
    {
        chomp($Mtik::error_msg);
        $Mtik::error_msg .= "\nWireless access list not loaded\n";
        return -1;
    }
    return(defined($wireless_macs{$mac}));
}

sub mtik_wireless_access_add
{
    my(%attrs) = %{(shift)};
    # first lets check to see if this MAC already exists
    my($exists) = mtik_wireless_access_mac_exists($attrs{'mac-address'});
    if ($exists != 0)
    {
        if ($exists > 0)
        {
            print "Wireless MAC already on access list: $attrs{'mac-address'}\n";
        }
        else
        {
            print "Unknow error: $Mtik::error_msg\n";
        }
        return 0;
    }
    
    # doesn't exist, so go ahead and add it
    my($retval,@results) = Mtik::mtik_cmd('/interface/wireless/access-list/add',\%attrs);
    if ($retval == 1)
    {
        # Mtik ID of the added item will be in $results[0]{'ret'}
        my($mtik_id) = $results[0]{'ret'};
        if ($Mtik::debug)
        {
            print "New Mtik ID: $mtik_id\n";
        }
        return $mtik_id;
    }
    else
    {
        # Error message will be in $Mtik::error_msg
        print "Unknown error: $Mtik::error_msg\n";
        return 0;
    }
}

sub mtik_wireless_access_set_by_mac
{
    my($mac) = shift;
    my(%attrs) = %{(shift)};
    # First we need to get the internal ID for the one we want to change.
    my(%wireless_macs) = &mtik_wireless_access_get_macs();
    if (my $mtik_id = $wireless_macs{$mac}{'.id'})
    {
        $attrs{'.id'} = $mtik_id;
        my($retval,@results) = Mtik::mtik_cmd('/interface/wireless/access-list/set',\%attrs);
        if ($retval == 1)
        {
            return 1;
        }
        # Error message will be in $Mtik::error_msg
        print "Unknown error: $Mtik::error_msg\n";
        return 0;
    }
    if ($Mtik::debug > 0)
    {
        print "MAC not found: $mac\n";
    }
    return 0;
}

sub mtik_wireless_access_get_by_mac
{
    my($mac) = shift;
    # even if we already fetched the acl list, we need to fetch it again
    # in case someone else has changed it.
    my(%wireless_macs) = &mtik_wireless_access_get_macs();
    return %{$wireless_macs{$mac}};
}

###############################################################################
######
###### Example test code
######
###### Obviously remove this section and replace with ...
###### 1;
###### ... if you want to use the above as library code.
######
###############################################################################

# CHANGE THESE to suit your environment.  Make sure $test_mac does NOT exist
# on the $mtik_host, as this test code will add / modify an ACL for it.
my($mtik_host) = '192.168.12.2';
my($mtik_username) = 'admin';
my($mtik_password) = 'mikeisamonkey';
my($test_mac) = '00:12:34:56:78:9B';

print "Logging in to Mtik: $mtik_host\n";
if (Mtik::login($mtik_host,$mtik_username,$mtik_password))
{   
    # add a new wireless ACL.
    print "\nAdding new ACL for MAC: $test_mac\n";
    my(%attrs);
    $attrs{'mac-address'} = $test_mac;
    $attrs{'ap-tx-limit'} = '0';
    $attrs{'authentication'} = 'yes';
    $attrs{'client-tx-limit'} = '0';
    $attrs{'comment'} = "HUGH TEST";
    $attrs{'forwarding'} = 'no';
    $attrs{'interface'} = 'wlan1';
    $attrs{'private-algo'} = 'none';
    $attrs{'private-key'} = '';
    $attrs{'private-pre-shared-key'} = '';
    $attrs{'signal-range'} = '-120.120';
    if (my $mtik_id = &mtik_wireless_access_add(\%attrs))
    {
        print "Added new ACL for $test_mac with id: $mtik_id\n";
    }
    
    print "\nGetting ACL attributes for MAC: $test_mac\n";
    my(%attrs2) = &mtik_wireless_access_get_by_mac($test_mac);
    foreach my $attr (keys(%attrs2))
    {
        print "   $attr: $attrs2{$attr}\n"
    }
    
    # change attributes for a wireless ACL with a specified MAC.
    print "\nChanging attributes for $test_mac\n";
    my(%attrs3);
    $attrs3{'forwarding'} = 'yes';
    $attrs3{'comment'} = "SCOOBYDOO";
    if (&mtik_wireless_access_set_by_mac($test_mac,\%attrs3))
    {
        print "Set ACL attributes for MAC: $test_mac\n";
    }
    
    print "\nGetting ACL attributes for MAC: $test_mac\n";
    my(%attrs4) = &mtik_wireless_access_get_by_mac($test_mac);
    foreach my $attr (keys(%attrs4))
    {
        print "   $attr: $attrs4{$attr}\n"
    }

    Mtik::logout;
}

