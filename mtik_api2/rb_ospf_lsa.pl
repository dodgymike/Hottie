#!/usr/bin/perl -w
use strict;

use vars qw($error_msg $debug);
use Mtik;
use Socket;

use DBI;

use Data::Dumper;

$Mtik::debug = 2;

$|++;

my $dbname = 'hottie';
my $dbuser = 'hottie';
my $dbpass = 'hottieisamonkey';
my $dbhost = 'localhost';

my $dbh = DBI->connect("dbi:Pg:dbname=$dbname;host=$dbhost", $dbuser, $dbpass, {AutoCommit => 0});
my $hottie_alert_sth = $dbh->prepare('INSERT INTO hottie_alerts (source, destination, message) values (?, ?, ?)');
my $route_change_sth = $dbh->prepare('INSERT INTO route_change_events (route, state, names) values (?, ?, ?)');

my $route_change_stats_sth = $dbh->prepare("select min(event_time) as min_event_time, max(event_time) as max_event_time, count(*) as change_count, route, names from route_change_events where (CURRENT_TIMESTAMP - event_time) < interval '1 day' group by route, names order by count(*) desc");

# CHANGE THESE to suit your environment.  Make sure $test_mac does NOT exist
# on the $mtik_host, as this test code will add / modify an ACL for it.
my($mtik_host) = '192.168.12.2';
my($mtik_username) = 'hottie';
my($mtik_password) = 'monkeyhottie';

print "Logging in to Mtik: $mtik_host\n";
if (Mtik::login($mtik_host,$mtik_username,$mtik_password))
{   
	print "logged in\n";

	my %lsaData = ();
	my %routeData = ();

	while(1) {
		my @messages = ();

		$route_change_stats_sth->execute();
		my $route_stats = $route_change_stats_sth->fetchall_hashref('route');
		print "ROUTE_STATS: ", Dumper($route_stats), "\n";
		
		my %currentRouteData = ();
		my $routes = mtik_route_ospf_get_route();
		foreach my $route (@$routes) {
			my $cost = $route->{cost};
			my $area = $route->{area};
			my $gateway = $route->{gateway};
			my $instance = $route->{instance};
			my $state = $route->{state};
			my $dst_address = $route->{'dst-address'};
			my $interface = $route->{interface};
			my $id = $route->{'.id'};

			$currentRouteData{$dst_address} = $route;
			if(not defined $routeData{$dst_address}) {
				my @resolved_names = lookup_subnet_addresses($dst_address);
#				push @messages, map { "NEW ROUTE: $_" } @resolved_names;
				add_route_change_row($dst_address, 'NEW', join(',', @resolved_names));

				# check for a route with many changes over the last 24 hours
				my $route_row = $route_stats->{$dst_address};
				if(defined($route_row) and $route_row->{change_count} > 1) {
					my $message = "NEW ROUTE ". join(',', @resolved_names). " has changed (". ($route_row->{change_count} + 1). ") times over the last 24 hours";
					push @messages, $message;
					print $message, "\n";
				}

				$routeData{$dst_address} = $route;
			}
		}

		foreach my $route (values %routeData) {
			my $cost = $route->{cost};
			my $area = $route->{area};
			my $gateway = $route->{gateway};
			my $instance = $route->{instance};
			my $state = $route->{state};
			my $dst_address = $route->{'dst-address'};
			my $interface = $route->{interface};
			my $id = $route->{'.id'};

			if(not defined $currentRouteData{$dst_address}) {
				delete $routeData{$dst_address};

				my @resolved_names = lookup_subnet_addresses($dst_address);
#				push @messages, map { "MISSING ROUTE: $_" } @resolved_names;
				add_route_change_row($dst_address, 'MISSING', join(',', @resolved_names));

				# check for a route with many changes over the last 24 hours
				my $route_row = $route_stats->{$dst_address};
				if(defined($route_row) and $route_row->{change_count} > 1) {
					my $message = "MISSING ROUTE ". join(',', @resolved_names). " has changed (". ($route_row->{change_count} + 1). ") times over the last 24 hours";
					push @messages, $message;
					print $message, "\n";
				}
			}
		}


#		print "MESSAGES: ", Dumper(\@messages), "\n";


		if(scalar(@messages) > 50) {
			@messages = "SOMETHING BAD HAPPENED - ".scalar(@messages)." messages were generated";
		}

#$VAR403 = {
#            'cost' => '97',
#            'area' => 'backbone',
#            'gateway' => '172.18.251.21',
#            'instance' => 'default',
#            'state' => 'intra-area',
#            'dst-address' => '172.18.255.252/30',
#            'interface' => 'OSPF-BMD',
#            '.id' => '*10041498'
#          };


		foreach my $message (@messages) {
			#`/etc/zabbix/alert.d/hottie_alert.sh '#ctwug-ospf' 'OSPF' '$message'`
			add_hottie_alert('hottie', '#ctwug-ospf', $message);
		}
		$dbh->commit;

		print "==========================\n";
		print "MESSAGES:\n";
		print Dumper(sort @messages);
		print "==========================\n";

		sleep(15);
	}

    Mtik::logout;

	print "done\n";
}


#{
#'options' => 'E',
#'originator' => '172.18.253.242',
#'area' => 'backbone',
#'age' => '713',
#'instance' => 'default',
#'checksum' => '42654',
#'sequence-number' => '2147483652',
#'.id' => '*10087C28',
#'type' => 'network',
#'id' => '172.18.254.149',
#'body=netmask' => '255.255.255.252'
#}


sub lookup_subnet_addresses {
	my $network = shift;

	my ($o1, $o2, $o3, $o4, $mask) = ($network) =~ /^\s*(\d+)\.(\d+)\.(\d+)\.(\d+)\/(\d+)\s*$/;
	my $prefix = "$o1.$o2.$o3.";

	my @names = ();
	if($mask eq '30') {
		my $lookupIp1 = $prefix.($o4 + 1);
		my $lookupName1 = lookup($lookupIp1);
		my $lookupIp2 = $prefix.($o4 + 2);
		my $lookupName2 = lookup($lookupIp2);

		push @names, "network ($network) - 1st ip ($lookupIp1/$lookupName1) 2nd ip ($lookupIp2/$lookupName2)";
	} elsif($mask eq '32') {
		my $lookupIp = $prefix.($o4);
		my $lookupName = lookup($lookupIp);

		push @names, "ip ($lookupIp) name ($lookupName)";
	} else {
		push @names, $network;
	}

	return @names;
}

sub lookup {
	my $address = shift;
	print "LOOKING UP ADDRESS ($address) - ";

	my $iaddr = inet_aton($address); # or whatever address
	my $name = gethostbyaddr($iaddr, AF_INET);

	my $result = $name;
	if(defined $result) {
		print "\tRESULT ($result)\n";
	} else {
		print "\t!!!UNKNOWN IP ($address)\n";
	}

	return defined($result) ? $result : '';
}

sub mtik_route_ospf_get_lsa {
	my($rv, @lsas) = Mtik::mtik_cmd('/routing/ospf/lsa/print', {});
	if($Mtik::error_msg eq '') {
		return \@lsas;
	}
	
	return undef;
}

sub mtik_route_ospf_get_route {
        my($rv, @routes) = Mtik::mtik_cmd('/routing/ospf/route/print', {});
        if($Mtik::error_msg eq '') {
                return \@routes;
        }

        return undef;
}

sub add_route_change_row {
	my $route = shift;	# The original route
	my $state = shift;	# NEW/REMOVED
	my $names = shift;	# the DNS names

	$route_change_sth->execute($route, $state, $names); # = $dbh->prepare('INSERT INTO route_change_events (route, state, names) values (?, ?, ?)');
}


sub add_hottie_alert {
	my $source = shift;
	my $destination = shift;
	my $message = shift;

	$hottie_alert_sth->execute($source, $destination, $message); # = $dbh->prepare('INSERT INTO hottie_alerts (source, destination, message) values (?, ?, ?)');
}

1;


__END__
create table route_change_events (id serial, event_time timestamp not null default CURRENT_TIMESTAMP, route text, state text, names text);

hottie=> \d hottie_alerts
                                      Table "public.hottie_alerts"
   Column    |            Type             |                         Modifiers                          
-------------+-----------------------------+------------------------------------------------------------
 id          | integer                     | not null default nextval('hottie_alerts_id_seq'::regclass)
 alert_time  | timestamp without time zone | not null default now()
 source      | text                        | 
 destination | text                        | 
 message     | text                        | 
 sent        | boolean                     | default false

